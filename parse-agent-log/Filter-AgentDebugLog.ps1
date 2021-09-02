<#
.SYNOPSIS
agent-debug.log を解析します。

.DESCRIPTION
このスクリプトは指定したディレクトリ配下に存在する agent-debug.log を再帰的に探索し、各ファイルから以下の内容を抽出します
    ノード起動時に付与されるインスタンスメタデータ
    タスクの開始と終了
    コンテナイメージの Pull 開始 と終了
    コマンドラインの開始と終了


.EXAMPLE
PS> .\Filter-AgentDebugLog.ps1 -root './root-dir/'

.PARAMETER root
ノードエージェントログを格納するディレクトリ

#>

param(
    [parameter(Mandatory)]
    [string]
    $root
)

$parserDefinition = @(
    @{
        eventname = 'InstanceMetadata';
        module = 'agent';
        file = 'node_agent.py';
        method = 'main';
        pattern = 'bootinfo>> instance metadata: (?<metadata>.*$)'
    },
    @{
        eventname = 'TaskStateActive';
        module = 'agent.task.history';
        file = 'history.py';
        method = 'add_task_to_history';
        pattern = 'new state TaskStateActive added'
    },
    @{
        eventname = 'PullImageStart';
        module = 'agent.container.containerutil';
        file = 'containerutil.py';
        method = 'pull_container_images_async';
        pattern = 'Pulling image (?<image>.*)$'
    },
    @{
        eventname = 'PullImageEnd';
        module = 'agent.container.containerutil';
        file = 'containerutil.py';
        method = 'pull_container_images_async';
        pattern = "pull images status: (?<status>.*)$"
    },
    @{
        eventname = 'CommandStart';
        module = 'agent.task.process';
        file = 'process.py';
        method = 'create_container_process_async';
        pattern = 'task=(?<account>[^\$]+)\$(?<jobid>[^\$]+)\$(?<job>[^\$]+)\$(?<taskid>[^\$]+)\$(?<seq>\d+) process pid=(?<pid>\d+) spawned'
    },
    @{
        eventname = 'CommandExit';
        module = 'agent.task.process';
        file = 'process.py';
        method = 'spawn_task_process_async';
        pattern = 'task=(?<account>[^\$]+)\$(?<jobid>[^\$]+)\$(?<job>[^\$]+)\$(?<taskid>[^\$]+)\$(?<seq>\d+) process exited: pid=(?<pid>\d+) exitcode=(?<exitcode>\d+)'
    },
    @{
        eventname = 'TaskStateCompleted';
        module = 'agent.task.history';
        file = 'history.py';
        method = 'add_task_to_history';
        pattern = 'new state TaskStateCompleted added'
    }
)


function Main()
{
    $logs = Get-ChildItem $root -Filter "agent-debug.log" -Recurse 
    $logs | foreach {
        $log = $_
        $results = @{node = $log.Directory.Parent.Name}
        
        $lines = Get-Content -Path $log.FullName
        $results.history = $lines | foreach { TryParse-EachLine -line $_  }
        return [PSCustomObject]$results
    }
}


function TryParse-EachLine([string]$line)
{
    $history = @()
    $columns = $line.Split('■')
    $parserDefinition | foreach {
        if($columns[5] -eq $_.module -and $columns[6] -eq $_.file -and $columns[7] -eq $_.method )
        {
            if($columns[12] -match $_.pattern)
            {
                $record = @{
                    timestamp = Get-TimeStamp $columns[2];
                    eventname = $_.eventname;
                    properties = @{ };
                    raw = $line;
                }
                $Matches.Keys | where { $_ -is [string]} | foreach {
                    $record.properties[$_] = $Matches[$_]
                }
                $history += [pscustomobject]$record
            }
        }
    }
    return $history
}

function Get-TimeStamp([string]$tsstring) 
{
    return [DateTimeOffset]::ParseExact($tsstring, 'yyyyMMddTHHmmss.fffZ', $null)
}




Main