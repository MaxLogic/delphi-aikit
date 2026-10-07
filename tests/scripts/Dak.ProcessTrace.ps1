#Requires -Version 5.1
# Development verification helper (T-329): runs one command inside a Windows job object and records every
# process the job reports, without administrator rights. Each process created in the job, including the
# root, is announced through the job's completion port and its image path is read immediately. The job's
# own accounting total is compared with the announced processes, so a missed notification makes the
# evidence incomplete instead of silently clean. Processes started outside the job (for example Windows
# executables launched by WSL interop) are not visible here, and the caller must say so.

if (-not ('DakProcessTrace.JobTracer' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace DakProcessTrace
{
    public sealed class TracedProcess
    {
        public int ProcessId;
        public string Image;
    }

    public sealed class TraceResult
    {
        public int ExitCode;
        public bool TimedOut;
        public uint JobTotalProcesses;
        public uint ActiveProcesses;
        public bool CleanupComplete;
        public List<TracedProcess> Processes = new List<TracedProcess>();
    }

    public static class JobTracer
    {
        const uint CREATE_SUSPENDED = 0x4;
        const uint CREATE_UNICODE_ENVIRONMENT = 0x400;
        const uint CREATE_NO_WINDOW = 0x08000000;
        const int STARTF_USESTDHANDLES = 0x100;
        const uint GENERIC_WRITE = 0x40000000;
        const uint GENERIC_READ = 0x80000000;
        const uint FILE_SHARE_READ = 1;
        const uint FILE_SHARE_WRITE = 2;
        const uint CREATE_ALWAYS = 2;
        const uint OPEN_EXISTING = 3;
        const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        const uint SYNCHRONIZE = 0x00100000;
        const uint ERROR_INVALID_PARAMETER = 87;
        const uint WAIT_OBJECT_0 = 0;
        const uint MSG_ACTIVE_PROCESS_ZERO = 4;
        const uint MSG_NEW_PROCESS = 6;
        const uint WAIT_TIMEOUT = 258;
        const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

        [StructLayout(LayoutKind.Sequential)]
        struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public bool bInheritHandle; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
            public int dwX; public int dwY; public int dwXSize; public int dwYSize; public int dwXCountChars;
            public int dwYCountChars; public int dwFillAttribute; public int dwFlags; public short wShowWindow;
            public short cbReserved2; public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_ASSOCIATE_COMPLETION_PORT { public IntPtr CompletionKey; public IntPtr CompletionPort; }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
        {
            public long TotalUserTime; public long TotalKernelTime; public long ThisPeriodTotalUserTime;
            public long ThisPeriodTotalKernelTime; public uint TotalPageFaultCount; public uint TotalProcesses;
            public uint ActiveProcesses; public uint TotalTerminatedProcesses;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct IO_COUNTERS
        {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr CreateIoCompletionPort(IntPtr fileHandle, IntPtr existingPort, UIntPtr key, uint threads);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_ASSOCIATE_COMPLETION_PORT info, int length);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, int length);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool QueryInformationJobObject(IntPtr job, int infoClass, out JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info, int length, IntPtr returnLength);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateProcess(IntPtr process, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcessW(string application, StringBuilder commandLine, IntPtr processAttributes,
            IntPtr threadAttributes, bool inheritHandles, uint flags, string environment, string directory,
            ref STARTUPINFO startup, out PROCESS_INFORMATION info);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetQueuedCompletionStatus(IntPtr port, out uint bytes, out UIntPtr key, out IntPtr overlapped, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder name, ref uint size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint GetProcessId(IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool inJob);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES attributes,
            uint disposition, uint flags, IntPtr template);

        static string ImageOf(IntPtr process)
        {
            var name = new StringBuilder(1024);
            uint size = (uint)name.Capacity;
            if (!QueryFullProcessImageNameW(process, 0, name, ref size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "query owned process image");
            return name.ToString();
        }

        static void WaitForOwnedProcess(IntPtr process, Stopwatch cleanupWatch)
        {
            uint state = WaitForSingleObject(process, 0);
            if (state == WAIT_OBJECT_0) return;
            if (state != WAIT_TIMEOUT)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "check owned process completion");
            int remaining = Math.Max(0, 10000 - (int)cleanupWatch.ElapsedMilliseconds);
            if (remaining == 0) throw new TimeoutException("Owned process cleanup did not complete within 10 seconds.");
            state = WaitForSingleObject(process, (uint)remaining);
            if (state == WAIT_TIMEOUT) throw new TimeoutException("Owned process cleanup did not complete within 10 seconds.");
            if (state != WAIT_OBJECT_0)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "wait for owned process completion");
        }

        static IntPtr InheritableFile(string path, uint access, uint disposition)
        {
            var attributes = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = true };
            IntPtr handle = CreateFileW(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, ref attributes, disposition, 0, IntPtr.Zero);
            if (handle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), path);
            return handle;
        }

        static JOBOBJECT_BASIC_ACCOUNTING_INFORMATION JobAccounting(IntPtr job)
        {
            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
            if (!QueryInformationJobObject(job, 1, out accounting, Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)), IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "query job accounting");
            return accounting;
        }

        static void WaitForJobEmpty(IntPtr job, Stopwatch cleanupWatch)
        {
            while (JobAccounting(job).ActiveProcesses != 0)
            {
                if (cleanupWatch.ElapsedMilliseconds >= 10000)
                    throw new TimeoutException("Owned job cleanup did not complete within 10 seconds.");
                System.Threading.Thread.Sleep(10);
            }
        }

        public static TraceResult Run(string commandLine, string workingDirectory, IDictionary<string, string> environment,
            string stdoutPath, string stderrPath, int timeoutMilliseconds)
        {
            if (timeoutMilliseconds <= 0) throw new ArgumentOutOfRangeException("timeoutMilliseconds");
            var result = new TraceResult();
            var keys = new List<string>(environment.Keys);
            keys.Sort(StringComparer.OrdinalIgnoreCase);
            var block = new StringBuilder();
            foreach (var key in keys)
                if (environment[key] != null) block.Append(key).Append('=').Append(environment[key]).Append('\0');
            block.Append('\0');

            IntPtr job = CreateJobObjectW(IntPtr.Zero, null);
            IntPtr port = CreateIoCompletionPort(new IntPtr(-1), IntPtr.Zero, UIntPtr.Zero, 1);
            IntPtr input = IntPtr.Zero, output = IntPtr.Zero, error = IntPtr.Zero;
            var info = new PROCESS_INFORMATION();
            bool assigned = false;
            Stopwatch cleanupWatch = null;
            var ownedHandles = new List<IntPtr>();
            var observedIds = new HashSet<int>();
            try
            {
                if (job == IntPtr.Zero || port == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "create job/completion port");
                // DS-687: exceptions must not orphan children already assigned to our job.
                var limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                if (!SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf(limits)))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "set job kill-on-close");
                var association = new JOBOBJECT_ASSOCIATE_COMPLETION_PORT { CompletionKey = job, CompletionPort = port };
                if (!SetInformationJobObject(job, 7, ref association, Marshal.SizeOf(association)))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "associate completion port");
                input = InheritableFile("NUL", GENERIC_READ, OPEN_EXISTING);
                output = InheritableFile(stdoutPath, GENERIC_WRITE, CREATE_ALWAYS);
                error = InheritableFile(stderrPath, GENERIC_WRITE, CREATE_ALWAYS);
                var startup = new STARTUPINFO { cb = Marshal.SizeOf(typeof(STARTUPINFO)), dwFlags = STARTF_USESTDHANDLES,
                    hStdInput = input, hStdOutput = output, hStdError = error };
                if (!CreateProcessW(null, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, true,
                    CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, block.ToString(), workingDirectory,
                    ref startup, out info))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), commandLine);
                if (!AssignProcessToJobObject(job, info.hProcess))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "assign process to job");
                assigned = true;
                result.Processes.Add(new TracedProcess { ProcessId = info.dwProcessId, Image = ImageOf(info.hProcess) });
                observedIds.Add(info.dwProcessId);
                if (ResumeThread(info.hThread) == UInt32.MaxValue)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "resume owned process");

                var watch = Stopwatch.StartNew();
                while (true)
                {
                    int remaining = (int)Math.Max(0, timeoutMilliseconds - watch.ElapsedMilliseconds);
                    if (remaining <= 0)
                    {
                        result.TimedOut = true;
                        if (!TerminateJobObject(job, 124))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "terminate timed-out job");
                        cleanupWatch = Stopwatch.StartNew();
                        WaitForJobEmpty(job, cleanupWatch);
                        break;
                    }
                    uint message; UIntPtr key; IntPtr data;
                    if (!GetQueuedCompletionStatus(port, out message, out key, out data, (uint)remaining))
                    {
                        if (Marshal.GetLastWin32Error() == WAIT_TIMEOUT) continue;
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "completion port");
                    }
                    if (message == MSG_NEW_PROCESS)
                    {
                        int processId = data.ToInt32();
                        if (observedIds.Add(processId))
                        {
                            IntPtr process = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
                            if (process == IntPtr.Zero)
                            {
                                int openError = Marshal.GetLastWin32Error();
                                if (openError != ERROR_INVALID_PARAMETER)
                                    throw new Win32Exception(openError, "open owned process");
                                // The job announced a process that exited before its PID could be opened.
                                // Leave the missing image visible so the trace cannot claim completeness.
                                result.Processes.Add(new TracedProcess { ProcessId = processId });
                            }
                            else
                            {
                                ownedHandles.Add(process);
                                uint openedId = GetProcessId(process);
                                if (openedId == 0)
                                    throw new Win32Exception(Marshal.GetLastWin32Error(), "identify owned process");
                                bool inJob;
                                if (openedId != (uint)processId)
                                    throw new InvalidOperationException("Announced process ID did not match its retained handle.");
                                if (!IsProcessInJob(process, job, out inJob))
                                    throw new Win32Exception(Marshal.GetLastWin32Error(), "verify owned process membership");
                                if (!inJob) throw new InvalidOperationException("Announced process ID was recycled outside the owned job.");
                                result.Processes.Add(new TracedProcess { ProcessId = processId, Image = ImageOf(process) });
                            }
                        }
                    }
                    else if (message == MSG_ACTIVE_PROCESS_ZERO) break;
                }
                if (cleanupWatch == null) cleanupWatch = Stopwatch.StartNew();
                WaitForJobEmpty(job, cleanupWatch);
                WaitForOwnedProcess(info.hProcess, cleanupWatch);
                foreach (var process in ownedHandles) WaitForOwnedProcess(process, cleanupWatch);
                uint exitCode;
                if (!GetExitCodeProcess(info.hProcess, out exitCode))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "read owned process exit code");
                result.ExitCode = unchecked((int)exitCode);
                var accounting = JobAccounting(job);
                result.JobTotalProcesses = accounting.TotalProcesses;
                result.ActiveProcesses = accounting.ActiveProcesses;
                result.CleanupComplete = accounting.ActiveProcesses == 0 &&
                    accounting.TotalProcesses == result.Processes.Count;
                if (!result.CleanupComplete) throw new InvalidOperationException("Owned process accounting or native completion is incomplete.");
                return result;
            }
            catch (Exception failure)
            {
                try
                {
                    if (assigned)
                    {
                        if (!TerminateJobObject(job, 125))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "terminate failed job");
                        if (cleanupWatch == null) cleanupWatch = Stopwatch.StartNew();
                        WaitForJobEmpty(job, cleanupWatch);
                        WaitForOwnedProcess(info.hProcess, cleanupWatch);
                        foreach (var process in ownedHandles) WaitForOwnedProcess(process, cleanupWatch);
                    }
                    else if (info.hProcess != IntPtr.Zero)
                    {
                        if (!TerminateProcess(info.hProcess, 125))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "terminate unassigned suspended process");
                        if (cleanupWatch == null) cleanupWatch = Stopwatch.StartNew();
                        WaitForOwnedProcess(info.hProcess, cleanupWatch);
                    }
                }
                catch (Exception cleanupFailure) { throw new AggregateException(failure, cleanupFailure); }
                throw;
            }
            finally
            {
                foreach (var process in ownedHandles) CloseHandle(process);
                if (info.hThread != IntPtr.Zero) CloseHandle(info.hThread);
                if (info.hProcess != IntPtr.Zero) CloseHandle(info.hProcess);
                foreach (var handle in new[] { input, output, error }) if (handle != IntPtr.Zero) CloseHandle(handle);
                CloseHandle(port);
                CloseHandle(job);
            }
        }
    }
}
'@
}

function Invoke-TracedProcess {
    # Runs a command line inside a job and returns exit code, output and every process the job created.
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][hashtable]$Environment,
        [Parameter(Mandatory)][string]$LogPath,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 900,
        [switch]$NoOutputText,
        [string]$StdoutPath = '',
        [string]$StderrPath = ''
    )
    $map = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) { $map[[string]$entry.Key] = [string]$entry.Value }
    foreach ($name in $Environment.Keys) { $map[$name] = $Environment[$name] }
    if ([string]::IsNullOrWhiteSpace($StdoutPath)) { $StdoutPath = "$LogPath.stdout" }
    if ([string]::IsNullOrWhiteSpace($StderrPath)) { $StderrPath = "$LogPath.stderr" }
    $trace = [DakProcessTrace.JobTracer]::Run($CommandLine, $WorkingDirectory, $map, $StdoutPath, $StderrPath, $TimeoutSeconds * 1000)
    $processes = @($trace.Processes | ForEach-Object { [pscustomobject]@{ pid = $_.ProcessId; image = $_.Image } })
    return [pscustomobject]@{
        command_line = $CommandLine
        working_directory = $WorkingDirectory
        exit_code = $trace.ExitCode
        timed_out = $trace.TimedOut
        job_total_processes = [int]$trace.JobTotalProcesses
        active_processes = [int]$trace.ActiveProcesses
        cleanup_complete = $trace.CleanupComplete
        processes = $processes
        complete = (-not $trace.TimedOut) -and ($processes.Count -eq [int]$trace.JobTotalProcesses) -and
            (@($processes | Where-Object { -not $_.image }).Count -eq 0)
        stdout_path = $StdoutPath
        stderr_path = $StderrPath
        stdout = if ($NoOutputText) { $null } else { [IO.File]::ReadAllText($StdoutPath) }
        stderr = if ($NoOutputText) { $null } else { [IO.File]::ReadAllText($StderrPath) }
    }
}
