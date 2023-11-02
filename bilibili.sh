#! /usr/bin/bash
#
height=$(stty size | awk '{print $1}')
width=$(stty size | awk '{print $2}')
height=$((height/3))
width=$((width/2))

RTMP_SERVER=""
RTMP_KEY=""
VIDEO_DIR=""
VIDEO_FILE_SUFFIX="*.mp4"
SERVICE_NAME="bilibili"

STATUS="scriptInit"
EVENT=""

scriptPreInit() {
	PACKAGES=""
	which ffmpeg >/dev/null 2>&1 || PACKAGES="${PACKAGES} ffmpeg"
	which whiptail >/dev/null 2>&1 || PACKAGES="${PACKAGES} whiptail"
	test ! -z "${PACKAGES}" && apt install -y ${PACKAGES}
	STATUS="scriptInit"
}

scriptInit() {
	if [ $(id -u) != 0 ]; then
			whiptail --clear --title "错误" --msgbox "需要root权限执行!\n当前UID：$(id -u)" ${height} ${width}
		#exit 1
	fi
	STATUS="setServer"
}

scripErrStatus() {
	echo "错误: 未知状态: ${STATUS}"
	STATUS="scriptErrExit"
}

setServer() {
	rtmp_svr=$(whiptail --clear --title "设置直播源地址" --inputbox "服务器地址：（rtmp://...）" ${height} ${width} 3>&1 1>&2 2>&3 )
	if [ $? != 0 ]; then
			# 取消输入
			STATUS="scriptExit"
	elif [ -z ${rtmp_svr} ]; then
			EVENT="InputEmpty"
	elif [ -z $(echo "${rtmp_svr}" | awk '/^rtmp:\/\//') ]; then
			EVENT="ServerURLError"
	else
			RTMP_SERVER=${rtmp_svr}
			STATUS="setKey"
	fi
}

setKey() {
	rtmp_key=$(whiptail --clear --title "设置串流密钥" --inputbox "输入串流密钥" ${height} ${width} 3>&1 1>&2 2>&3 )
	if [ $? != 0 ]; then
			# 取消输入，回退上层
			STATUS="setServer"
	elif [ -z "${rtmp_key}" ]; then
			EVENT="InputEmpty"
	else
			RTMP_KEY=${rtmp_key}
			STATUS="setVideoDir"
	fi
}

setVideoDir() {
	STATUS="scriptExit"
	input_val=$(whiptail --clear --title "设置视频目录" --inputbox "输入路径(/xxx/xxx...)" ${height} ${width} 3>&1 1>&2 2>&3 )
	if [ $? != 0 ]; then
			# 取消输入，回退上层
			STATUS="setKey"
			return 
	elif [ -z "${input_val}" ]; then
			EVENT="InputEmpty"
			return
	fi
	#检查路径
	if [ -z "$(echo ${input_val} | awk '/^\//')" ]; then
		VIDEO_DIR="$(pwd)/${input_val}"
	else
		VIDEO_DIR="${input_val}"
	fi
	#检查路径存在
	if [ ! -d "${VIDEO_DIR}" ]; then
			EVENT="VideoDirNotExists"
			return
	fi
	
	_VideoFilesExists=0
	for suffix in "${VIDEO_FILE_SUFFIX}"; do
		ls ${VIDEO_DIR}/${suffix} > /dev/null 2>&1
		test $? == 0 && _VideoFilesExists=1
	done

	if [ ${_VideoFilesExists} == 0 ]; then
			EVENT="VideoFileNotFound"
			return
	fi

	STATUS="configPost"
}

configPost() {
		svr_info="服务器：${RTMP_SERVER::10}...\n"
		key_info="直播密钥：${RTMP_KEY::10}...\n"
		dir_info="视频目录：\n${VIDEO_DIR} \n"
		info="应用当前配置？\n${svr_info}${key_info}${dir_info}"

		whiptail --clear --title "确认" \
				--yesno "${info}" ${height} ${width}
		test $? == 0 && STATUS="genSystemConfig" || STATUS="scriptExit"
}


##生成systemd配置
createSystemdServiceConf() {
	CPU=2
	CPUQuota="${CPU}00%"

	cat > /etc/default/${SERVICE_NAME} << EOF
FFMPEG_GLOBAL_ARGS="-re -threads ${CPU} -stream_loop -1"
FFMPEG_INPUT_ARGS=""
FFMPEG_OUTPUT_ARGS="-c:v copy -c:a copy"
RTMP_SERVER="${RTMP_SERVER}"
RTMP_KEY="${RTMP_KEY}"	
EOF

	cat > /lib/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]

[Service]
Type=simple
EnvironmentFile=/etc/default/${SERVICE_NAME}
WorkingDirectory=${VIDEO_DIR}
ExecStartPre=/usr/bin/bash -c 'ls -1 ${VIDEO_FILE_SUFFIX} | xargs -I {} echo -e "file \x27{}\x27" >> playlist.txt'
ExecStart=/usr/bin/ffmpeg \$FFMPEG_GLOBAL_ARGS -safe 0 -f concat \$FFMPEG_INPUT_ARGS -i playlist.txt \$FFMPEG_OUTPUT_ARGS -f flv  \${RTMP_SERVER}\${RTMP_KEY}
ExecStopPost=-/bin/rm playlist.txt
EOF
}

genSystemConfig() {
	createSystemdServiceConf
	systemctl daemon-reload
	systemctl restart ${SERVICE_NAME}
	STATUS="scriptExit"
}

event_handler_InputEmpty() {
		whiptail --clear  --title "${STATUS} 警告" \
				--yesno "输入为空，是否重新输入？" ${height} ${width} || STATUS="scriptErrExit"
}

event_handler_ServerURLError() {
	# 输入非法处理
	whiptail --clear --title "设置服务器地址错误" \
		--yesno "输入的rtmp://服务器地址格式错误，是否重新输入？" ${height} ${width} \
		&& STATUS="setServer" \
		|| STATUS="scriptErrExit"
}

event_handler_VideoDirNotExists() {
	# 输入非法处理
	whiptail --clear --title "设置视频目录：错误" \
		--yesno "${VIDEO_DIR} \n目录不存在，是否重新输入？" ${height} ${width} \
		&& STATUS="setVideoDir" \
		|| STATUS="scriptErrExit"
}

event_handler_VideoDirReadPermissionError() {
	STATUS="scriptErrExit"
}


event_handler_VideoFileNotFound() {	
	whiptail --clear --title "警告" \
		--yesno "${VIDEO_DIR} \n无视频文件，是否继续设置？" ${height} ${width} \
		&& STATUS="configPost" \
		|| STATUS="setVideoDir"
}

# scriptInit 开始
# scriptExit 退出
# setServer 服务器设置
# setKey 直播密钥设置
# setVideoDir 设置视频目录
# videoFilter 筛选视频格式
# genSystemConfig 生成systemd配置
# configPost 配置确认
#
# Event:
# ServerURLError  serverURL不合法
# InputEmpty 输入设置为空
# VideoDirNotExists 文件夹不存在
# VideoDirReadPermissionError 文件夹读权限故障
# VideoFileNotFound 视频文件不存在

# 状态处理
machine_ctrl() {
	case ${STATUS} in
		scriptInit)  scriptInit ;;
		scriptExit) exit 0 ;;
		scriptErrExit) exit 1 ;;
		configPost) configPost;;
		setServer) setServer ;;
		setKey) setKey ;;
		setVideoDir) setVideoDir;;
		genSystemConfig) genSystemConfig ;;
		*) scripErrStatus ;;
	esac
}

# 事件处理
event_ctrl() {
	case ${EVENT} in
		"") ;;
		InputEmpty) 
				event_handler_InputEmpty ;;
		ServerURLError) 
				event_handler_ServerURLError ;;
		VideoDirNotExists) 
				event_handler_VideoDirNotExists ;;
		VideoDirReadPermissionError) 
				event_handler_VideoDirReadPermissionError ;;	
		VideoFileNotFound) 
				event_handler_VideoFileNotFound ;;
		*)
				echo  "未知EVENT ${EVENT}"
	esac
	# 清空事件队列
	EVENT=""
}



mainloop() {
	scriptPreInit
	while true; do
			machine_ctrl
			event_ctrl
	done
}

mainloop
