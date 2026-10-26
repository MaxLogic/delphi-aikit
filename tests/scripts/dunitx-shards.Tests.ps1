BeforeAll { . (Join-Path $PSScriptRoot 'dunitx-shards.ps1') }
Describe 'Shard evidence' {
    It 'derives named fixtures and future FixInsight methods from the registered binary roster' {
        $roster = @(
            [pscustomobject]@{fixture='Test.Named.Named fixture';selector='Test.Named.Named fixture.FailureCase';id='Test.Named.Named fixture.FailureCase'},
            [pscustomobject]@{fixture='Test.FixInsight.TFixInsightTests';selector='Test.FixInsight.TFixInsightTests.FutureCase';id='Test.FixInsight.TFixInsightTests.FutureCase'},
            [pscustomobject]@{fixture='Test.FixInsight.TFixInsightTests';selector='Test.FixInsight.TFixInsightTests.FixInsightRawReportsPreserveFilteredEvidence';id='Test.FixInsight.TFixInsightTests.FixInsightRawReportsPreserveFilteredEvidence'})
        $groups = @(Get-DakFixtureGroup -TestsRoot (Split-Path $PSScriptRoot -Parent) -Roster $roster)
        $selectors = @($groups | ForEach-Object selectors)
        $selectors | Should -Contain 'Test.Named.Named fixture'
        $selectors | Should -Contain 'Test.FixInsight.TFixInsightTests.FutureCase'
    }
    It 'selects the whole ordinary fixture so comma-named parameterized cases reach DUnitX' {
        $roster = @(
            [pscustomobject]@{fixture='Test.Build.TBuildTests';selector='Test.Build.TBuildTests.Case.failed build, json';id='TBuildTests.Case.failed build, json'},
            [pscustomobject]@{fixture='Test.Build.TBuildTests';selector='Test.Build.TBuildTests.Case.successful build, text';id='TBuildTests.Case.successful build, text'})
        $groups = @(Get-DakFixtureGroup -TestsRoot (Split-Path $PSScriptRoot -Parent) -Roster $roster)
        $groups.Count | Should -Be 1
        @($groups[0].selectors).Count | Should -Be 1
        $groups[0].selectors[0] | Should -Be 'Test.Build.TBuildTests'
    }
    It 'rejects omissions and duplicates without requiring serial proof' {
        $roster = @([pscustomobject]@{id='Named.a'}, [pscustomobject]@{id='FixInsight.FutureCase'})
        $cases = @([pscustomobject]@{id='Named.a'}, [pscustomobject]@{id='Named.a'})
        $differences = @(Compare-DakRoster -Roster $roster -Cases $cases)
        $differences | Should -Contain 'Missing registered case: FixInsight.FutureCase'
        $differences | Should -Contain 'Duplicate executed case: Named.a'
    }
    It 'reads the runner summary without consuming nested fixture summaries' {
        $root = Join-Path $TestDrive 'logs'
        $runner = Join-Path $root 'run-0123456789abcdef0123456789abcdef'
        [void][IO.Directory]::CreateDirectory((Join-Path $runner 'migration\seeds'))
        '{"counts":{"Found":1}}' | Set-Content (Join-Path $runner 'summary.json')
        '{"fixture":"not a runner summary"}' | Set-Content (Join-Path $runner 'migration\seeds\summary.json')
        (Read-DakShardSummary $root).counts.Found | Should -Be 1
    }
    It 'counts an errored case inside a successful fixture' {
        $path = Join-Path $TestDrive 'error.xml'
        '<test-results><test-suite type="Fixture" name="Fixture" result="Success"><results><test-case name="one" result="Error" time="1"><failure><message>case error</message></failure></test-case></results></test-suite></test-results>' | Set-Content $path
        $cases = @(Read-DakCaseResult $path)
        $cases.Count | Should -Be 1
        $cases[0].result | Should -Be 'Error'
        $cases[0].detail | Should -Match 'case error'
        $merged = Merge-DakShardResult @([pscustomobject]@{ exitCode=0; processExitCode=0; counts=@{Found=1;Passed=1;Failed=0;Errored=0;Leaked=0;Ignored=0}; shutdownLeakReport=$false }) $cases
        $merged.exitCode | Should -Be 1
        $merged.counts.Errored | Should -Be 1
        $merged.counts.Passed | Should -Be 0
    }
    It 'keeps every footer failure, ignored test and shutdown leak' {
        $summary = [pscustomobject]@{exitCode=0;processExitCode=0;counts=@{Found=3;Passed=1;Failed=1;Errored=0;Leaked=0;Ignored=1};shutdownLeakReport=$true}
        $result = Merge-DakShardResult @($summary) @(
            [pscustomobject]@{id='F.a';result='Success';detail='';seconds=1},
            [pscustomobject]@{id='F.b';result='Failure';detail='bad';seconds=1},
            [pscustomobject]@{id='F.c';result='Ignored';detail='skip';seconds=1})
        $result.exitCode | Should -Be 1
        $result.counts.Failed | Should -Be 1
        $result.counts.Ignored | Should -Be 1
        $result.failures.Count | Should -Be 2
        $result.shutdownLeakReport | Should -BeTrue
    }
    It 'rejects duplicate identities and missing footer counts' {
        $case = [pscustomobject]@{id='F.a';result='Success';detail='';seconds=1}
        { Merge-DakShardResult @() @($case,$case) } | Should -Throw '*Duplicate*'
        (Merge-DakShardResult @([pscustomobject]@{exitCode=0;processExitCode=0;counts=$null;shutdownLeakReport=$false}) @($case)).exitCode | Should -Be 1
    }
    It 'balances measured groups without splitting the migration pair' {
        $plan = @(Get-DakShardPlan -Groups @(
            [pscustomobject]@{selectors=@('critical');seconds=1174},
            [pscustomobject]@{selectors=@('Replay','Verify');seconds=200},
            [pscustomobject]@{selectors=@('other');seconds=300}) -ShardCount 2)
        @($plan | ForEach-Object selectors | Sort-Object) -join ',' | Should -Be 'critical,other,Replay,Verify'
        @($plan | Where-Object { $_.selectors -contains 'Replay' })[0].selectors | Should -Contain 'Verify'
    }
}

Describe 'Fixture category contract' {
    It 'uses one comma-separated category attribute and preserves existing selectors' {
        $units = Join-Path (Split-Path $PSScriptRoot -Parent) 'units'
        foreach ($file in Get-ChildItem $units -Filter '*.pas') {
            $source = [IO.File]::ReadAllText($file.FullName)
            foreach ($fixture in [regex]::Matches($source, '(?is)\[TestFixture(?:\([^\]]*\))?\]\s*((?:\[[^\]]+\]\s*)*)(\w+)\s*=\s*class')) {
                $attributes = [regex]::Matches($fixture.Groups[1].Value, "\[Category\('([^']+)'\)\]")
                $attributes.Count | Should -Be 1 -Because $fixture.Groups[2].Value
                $categories = $attributes[0].Groups[1].Value.Split(',')
                @($categories | Where-Object { $_ -in 'Fast','Slow' }).Count | Should -Be 1
                if ($fixture.Groups[2].Value -in 'TRefactorProprietaryRenameTests','TRemoveWithProprietaryProjectTests') {
                    $categories | Should -Contain 'MaxTdbProof'
                }
                $preserved = @{ TRefactorPreflightTests='RefactoringLightPreflight'; TRefactorTransactionTests='RefactoringLightTransaction'; TSignatureCommandTests='RefactoringLightAlign' }
                if ($preserved.ContainsKey($fixture.Groups[2].Value)) { $categories | Should -Contain $preserved[$fixture.Groups[2].Value] }
            }
        }
    }
}

Describe 'Shard collection with native children' {
    BeforeAll {
        $emitter = Join-Path $TestDrive 'ShardEmitter.exe'
        $sourcePath = Join-Path $TestDrive 'ShardEmitter.cs'
        @'
using System;
using System.IO;
using System.Threading;
class ShardEmitter {
 static int Main(string[] args) {
  string roster=Environment.GetEnvironmentVariable("DAK_TEST_LIST_PATH");
  if(!String.IsNullOrEmpty(roster)) {
   File.WriteAllText(roster,"[{\"fixture\":\"Test.Build.TBuildTests\",\"selector\":\"Test.Build.TBuildTests.One\",\"id\":\"Test.Build.TBuildTests.One\"},{\"fixture\":\"Test.DfmCheck.TDfmCheckTests\",\"selector\":\"Test.DfmCheck.TDfmCheckTests.Two\",\"id\":\"Test.DfmCheck.TDfmCheckTests.Two\"},{\"fixture\":\"Test.DfmCheck.TDfmCheckTests\",\"selector\":\"Test.DfmCheck.TDfmCheckTests.Future\",\"id\":\"Test.DfmCheck.TDfmCheckTests.Future\"}]");
   return 0;
  }
  string xml=null,list=null;
  foreach(string arg in args) {if(arg.StartsWith("--xmlfile:")) xml=arg.Substring(10);if(arg.StartsWith("--runlist:")) list=arg.Substring(10);}
  bool first=new DirectoryInfo(Path.GetDirectoryName(list)).Name=="1";
  string fixture=first?"Test.DfmCheck.TDfmCheckTests":"Test.Build.TBuildTests";
  bool omit=Environment.GetEnvironmentVariable("DAK_SHARD_TEST_FAULT")=="omission";
  if(!first) Thread.Sleep(1800);
  string name=first?"Two":"One";
  string result=omit?"Success":"Failure";
  if(first && !omit) File.WriteAllText(xml,"<test-results><test-suite");
  else File.WriteAllText(xml,"<test-results><test-suite type=\"Fixture\" name=\""+fixture+"\"><results>"+((first && !omit)?"":"<test-case name=\""+name+"\" result=\""+result+"\" time=\"1.8\">"+(omit?"":"<failure><message>late failure</message></failure>")+"</test-case>")+"</results></test-suite></test-results>");
  Console.WriteLine("Tests Found : 1\nTests Ignored : 0\nTests Passed : "+(omit?"1":"0")+"\nTests Leaked : 0\nTests Failed : "+(omit?"0":"1")+"\nTests Errored : 0");
  return 0;
 }
}
'@ | Set-Content -LiteralPath $sourcePath
        & "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$emitter" $sourcePath
        if ($LASTEXITCODE -ne 0) { throw 'Emitter compilation failed.' }
    }
    It 'collects the later failure after another child writes truncated XML' {
        $logs = Join-Path $TestDrive 'collection'
        $output = [IO.Directory]::CreateTempSubdirectory('dak-').FullName
        & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot '..\run-shards.ps1') -ExecutablePath $emitter -LogRoot $logs -OutputRoot $output -ShardCount 2 -TimeoutSeconds 8 | Out-Null
        $nativeExit = $LASTEXITCODE
        [IO.Directory]::Delete($output, $true)
        $nativeExit | Should -Be 1
        $aggregate = Get-Content (Get-ChildItem $logs -Filter aggregate.json -Recurse).FullName -Raw | ConvertFrom-Json
        @($aggregate.shards | Where-Object { $null -eq $_.exitCode }).Count | Should -Be 0
        $aggregate.failures.detail | Should -Contain 'late failure'
        $aggregate.errors -join ' ' | Should -Match 'Shard .*XML'
    }
    It 'fails binary roster coverage when XML silently omits a registered case' {
        $logs = Join-Path $TestDrive 'omission'
        $output = [IO.Directory]::CreateTempSubdirectory('dak-').FullName
        try {
            $env:DAK_SHARD_TEST_FAULT = 'omission'
            & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot '..\run-shards.ps1') -ExecutablePath $emitter -LogRoot $logs -OutputRoot $output -ShardCount 2 -TimeoutSeconds 8 | Out-Null
        } finally { Remove-Item Env:DAK_SHARD_TEST_FAULT -ErrorAction SilentlyContinue }
        $nativeExit = $LASTEXITCODE
        [IO.Directory]::Delete($output, $true)
        $nativeExit | Should -Be 1
        $aggregate = Get-Content (Get-ChildItem $logs -Filter aggregate.json -Recurse).FullName -Raw | ConvertFrom-Json
        $aggregate.rosterDifferences | Should -Contain 'Missing registered case: Test.DfmCheck.TDfmCheckTests.Future'
        @($aggregate.shards | Where-Object exitCode -ne 0).Count | Should -Be 0
        $aggregate.failures.Count | Should -Be 0
        $aggregate.counts.Passed | Should -Be 2
    }
}
