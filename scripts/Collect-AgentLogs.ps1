<#
.SYNOPSIS
Azure Batch プール内の全ノードのエージェントログを収集します。

.DESCRIPTION
このスクリプトは Batch アカウントと関連付けられたストレージアカウントないに Blob コンテナを作成、各エージェントログがコンテナ内にアップロードされたのち、ローカル環境にダウンロードします。
全てのノードから各ノードがデプロイされて以降の全ログを収集するため、データ量が膨大になる可能性があるため注意してください。
スクリプト実行前に Batch アカウントおよびストレージアカウントに十分のアクセス権があるアカウントで Azure に接続 (Connect-AzAccount) してください。

.EXAMPLE
PS> Connect-AzAccount
PS> .\Collect-AgentLogs.ps1 -batchaccount 'yourAccountName' -poolid 'target-node-pool-id'

.PARAMETER batchaccount
バッチアカウント名を指定します。

.PARAMETER poolid
計算ノードが含まれるプールIDを指定します。

.LINK
Start-AzBatchComputeNodeServiceLogUpload

.LINK
Azure Batch のベストプラクティス: https://docs.microsoft.com/ja-jp/azure/batch/best-practices#nodes
#>

param(
    [parameter(Mandatory)]
    [string]
    $bachtaccount,
    [parameter(Mandatory)]
    [string]$poolid
)

# 指定したバッチアカウントとストレージアカウント情報を取得
$batctx = Get-AzBatchAccount -AccountName $bachtaccount 
$autostr = Get-AzResource -ResourceId $batctx.AutoStorageProperties.StorageAccountId 
$strctx = New-AzStorageContext -StorageAccountName $autostr.Name

# ログを保存するストレージコンテナの準備
$uploadcontainer = 'agentlogs-{0:yyyyMMdd-HHmmss}' -f [DateTime]::UtcNow
$container = New-AzStorageContainer  -Context $strctx -Name $uploadcontainer 
$sasstart = [DateTime]::UtcNow
$sasend = $sasstart.AddHours(3)
$sas = New-AzStorageContainerSASToken -Context $strctx  -Name $uploadcontainer -Permission rwdl -StartTime $sasstart -ExpiryTime $sasend
$uploadurl = "{0}{1}" -f $container.CloudBlobContainer.Uri, $sas

#各ノードの全エージェントログをストレージにアップロード
Write-Host "agent log will be uploaded to $($container.CloudBlobContainer.Uri)"
$pool = Get-AzBatchPool -BatchContext $batctx -Id $poolid

Get-AzBatchComputeNode -BatchContext $batctx -PoolId $poolid | foreach {
	Write-Host "uploading from $($_.Id) to storage"
	Start-AzBatchComputeNodeServiceLogUpload -BatchContext $batctx -ContainerUrl $uploadurl  -ComputeNode $_ -StartTime $_.AllocationTime
} | sv upresults

$upresults | foreach {
	$blobdir = $_.VirtualDirectoryName
	$dir = New-Item -ItemType Directory -Path $blobdir
	$logs = ('agent-debug.log', 'agent-warn.log', 'controller-debug.log', 'controller-warn.log')
	$logs | foreach {
		Write-Host "downloading from $blobdir/$_"
		$blob = Get-AzStorageBlobContent -Context $strctx -Container $uploadcontainer -Blob "$blobdir/$_" -Destination  "$($dir.FullName)/$_"
	}
}