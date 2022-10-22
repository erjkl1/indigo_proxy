#!/bin/bash

#一括でindigoの全てのVPNサーバーを立ち上げhttpd,squidインストール後proxyサーバーを起動する
#indigo = https://web.arena.ne.jp/indigo/
myip=`curl ipecho.net/plain`
echo "globalIp:$myip" #現在のグローバルIPアドレスを表示

namespace=~/proxy/ #指定したディレクトリ配下にsquid.confを配置する
squidConf="${namespace}squid.conf"

#上記で指定したsquid.confにプロキシサーバに対して自身のグローバルIPアドレスのみでアクセスできるように設定を書き換える
gsed -i 1d ~/proxy/squid.conf
gsed -i "1i acl testacl src $myip/32" "$squidConf" 

secretKey='~/.ssh/secret_key/private_key.txt'#SSH秘密キーのパスを指定

apiKey= #indigoのAPIキーを入力

apiSecretKey= #indigoのAPI秘密キーを入力

port=22 #VPNサーバーとSSH接続するためのポートを指定。デフォルトでは22

tokenSetting=`jq -n \
 --arg apiKey "$apiKey" \
 --arg apiSecretKey "$apiSecretKey" \
  '{
  	"grantType": "client_credentials",
    "clientId": $apiKey,
    "clientSecret": $apiSecretKey,
    "code": ""
  }'`

#Get accessToken
accessToken=`curl -X POST \
  https://api.customer.jp/oauth/v1/accesstokens \
  -H 'Content-Type: application/json' \
  -d "$tokenSetting" \
  | jq -r .accessToken`

#Get instances
instances=`curl -X GET \
  https://api.customer.jp/webarenaIndigo/v1/vm/getinstancelist \
  -H "Authorization: Bearer $accessToken" | jq  '.[] | {id: .id, ip: .ipaddress}'`

instances=`echo $instances | jq -s`

echo "$instances"

instanceCount=`echo ${instances} | jq length`

echo "instanceCount:$instanceCount"

for i in `seq 0 $((${instanceCount} - 1))`; do

	row=`echo ${instances} | jq .[${i}]`
	id=`echo ${row} | jq -r .id`
	ip=`echo ${row} | jq -r .ip`

	updateSetting=`jq -n \
	--arg id "$id" \
	'{
		"instanceId": $id,
		"status": "start",
	}'`

	echo "starting... $ip"
	#start instance
	startResult=`curl -X POST \
	https://api.customer.jp/webarenaIndigo/v1/vm/instance/statusupdate \
	-H "Authorization: Bearer $accessToken" \
	-d "$updateSetting" | jq -r .success,.errorCode`

	success=`echo $startResult | awk '{print $1}'`
	errorCode=`echo $startResult | awk '{print $2}'`

	echo "success:$success"
	echo "errorCode:$errorCode"

	 #サーバー起動成功または既に起動済みの場合はディレイを入れない
	echo "starting $ip"
	if [ $success = 'success' ] || [ $errorCode = 'I10016' ]; then
	echo "$ip is already started"
	#サーバー起動待機のためのディレイ
	else
		sleep 30
	fi;
	echo "starting $ip complete"

	echo 'httpd squid installing...' 
	sshpass ssh -n -o StrictHostKeyChecking=no -p $port centos@$ip -i $secretKey sudo yum -y install httpd;

	sshpass ssh -n -o StrictHostKeyChecking=no -p $port centos@$ip -i $secretKey sudo yum -y install squid;
	echo 'httpd squid install complete'

	echo 'squid.conf saving...'
	sshpass ssh -n -o StrictHostKeyChecking=no -p $port centos@$ip -i $secretKey sudo chmod 777 /etc/squid/squid.conf;
	sshpass scp -o StrictHostKeyChecking=no -P $port -i $secretKey $squidConf centos@$ip:/etc/squid/squid.conf
	echo 'squid.conf save complete'


	echo 'squid start'
	sshpass ssh -n -o StrictHostKeyChecking=no -p $port centos@$ip -i $secretKey sudo systemctl start squid
	echo 'K!'

done

echo indigoのプロキシ作成が終わりました
