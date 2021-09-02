<#
.SYNOPSIS
Azure Batch プール内の全ノードのエージェントログを収集します。

.DESCRIPTION
Azure Batch プール内の全ノードのエージェントログを収集します。
このスクリプトは Batch アカウントと関連付けられたストレージアカウントないに Blob コンテナを作成、各エージェントログがコンテナ内にアップロードされたのち、ローカル環境にダウンロードします。
全てのノードから各ノードがデプロイされて以降の全ログを収集するため、データ量が膨大になる可能性があるため注意してください。
スクリプト実行前に Batch アカウントおよびストレージアカウントに十分のアクセス権があるアカウントで Azure に接続 (Connect-AzAccount) してください。

#>

param(
    [string]$bachAccountName,
    [string]$pool
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
	 Start-AzBatchComputeNodeServiceLogUpload -BatchContext $batctx -ContainerUrl $uploadurl  -ComputeNode $_ -StartTime $_.AllocationTime
} | sv upresults

$upresults | foreach {
	$blobdir = $_.VirtualDirectoryName
	$dir = New-Item -ItemType Directory -Path $blobdir
	$logs = ('agent-debug.log', 'agent-warn.log', 'controller-debug.log', 'controller-warn.log')
	$logs | foreach {
		Get-AzStorageBlobContent -Context $strctx -Container $uploadcontainer -Blob "$blobdir/$_" -Destination  "$($dir.FullName)/$_"
	}
}