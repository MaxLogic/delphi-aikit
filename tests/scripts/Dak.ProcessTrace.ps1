#Requires -Version 7.0
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
        const uint MSG_ACTIVE_PROCESS_ZERO = 4;
        const uint MSG_NEW_PROCESS = 6;
        const uint WAIT_TIMEOUT = 258;

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

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr CreateIoCompletionPort(IntPtr fileHandle, IntPtr existingPort, UIntPtr key, uint threads);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_ASSOCIATE_COMPLETION_PORT info, int length);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool QueryInformationJobObject(IntPtr job, int infoClass, out JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info, int length, IntPtr returnLength);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateJobObject(IntPtr job, uint exitCode);
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
        static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES attributes,
            uint disposition, uint flags, IntPtr template);

        static string ImageOf(int processId)
        {
            IntPtr handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
            if (handle == IntPtr.Zero) return null;
            try
            {
                var name = new StringBuilder(1024);
                uint size = (uint)name.Capacity;
                return QueryFullProcessImageNameW(handle, 0, name, ref size) ? name.ToString() : null;
            }
            finally { CloseHandle(handle); }
        }

        static IntPtr InheritableFile(string path, uint access, uint disposition)
        {
            var attributes = new SECURITY_ATTRIBUTES { nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = true };
            IntPtr handle = CreateFileW(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, ref attributes, disposition, 0, IntPtr.Zero);
            if (handle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), path);
            return handle;
        }

        public static TraceResult Run(string commandLine, string workingDirectory, IDictionary<string, string> environment,
            string stdoutPath, string stderrPath, int timeoutMilliseconds)
        {
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
            try
            {
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
                ResumeThread(info.hThread);

                var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMilliseconds);
                while (true)
                {
                    int remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
                    if (remaining <= 0) { result.TimedOut = true; TerminateJobObject(job, 1); break; }
                    uint message; UIntPtr key; IntPtr data;
                    if (!GetQueuedCompletionStatus(port, out message, out key, out data, (uint)remaining))
                    {
                        if (Marshal.GetLastWin32Error() == WAIT_TIMEOUT) continue;
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "completion port");
                    }
                    if (message == MSG_NEW_PROCESS)
                    {
                        int processId = data.ToInt32();
                        result.Processes.Add(new TracedProcess { ProcessId = processId, Image = ImageOf(processId) });
                    }
                    else if (message == MSG_ACTIVE_PROCESS_ZERO) break;
                }
                WaitForSingleObject(info.hProcess, 10000);
                uint exitCode;
                result.ExitCode = GetExitCodeProcess(info.hProcess, out exitCode) ? unchecked((int)exitCode) : -1;
                JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
                if (QueryInformationJobObject(job, 1, out accounting, Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)), IntPtr.Zero))
                    result.JobTotalProcesses = accounting.TotalProcesses;
                return result;
            }
            finally
            {
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
        [int]$TimeoutSeconds = 900
    )
    $map = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) { $map[[string]$entry.Key] = [string]$entry.Value }
    foreach ($name in $Environment.Keys) { $map[$name] = $Environment[$name] }
    $trace = [DakProcessTrace.JobTracer]::Run($CommandLine, $WorkingDirectory, $map, "$LogPath.stdout", "$LogPath.stderr", $TimeoutSeconds * 1000)
    $processes = @($trace.Processes | ForEach-Object { [pscustomobject]@{ pid = $_.ProcessId; image = $_.Image } })
    return [pscustomobject]@{
        command_line = $CommandLine
        working_directory = $WorkingDirectory
        exit_code = $trace.ExitCode
        timed_out = $trace.TimedOut
        job_total_processes = [int]$trace.JobTotalProcesses
        processes = $processes
        complete = (-not $trace.TimedOut) -and ($processes.Count -eq [int]$trace.JobTotalProcesses) -and
            (@($processes | Where-Object { -not $_.image }).Count -eq 0)
        stdout = [IO.File]::ReadAllText("$LogPath.stdout")
        stderr = [IO.File]::ReadAllText("$LogPath.stderr")
    }
}
