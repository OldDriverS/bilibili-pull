# debian下部署ffmpeg推流视频到bilibili直播

## 准备

- bilibili开通直播，获取到 `rtmp` 服务器地址和 `串流密钥`

- 准备要播放的mp4文件放在某个目录，推荐 */opt/video*

# 部署

脚本会安装ffmpeg，但是没有换源，如果下载速度慢，应该换国内源了。


以下是换国内apt源的脚本，debian10以上可用，以下不是必须，但是安装源内的ffmpeg体积较大，看情况换，先注释掉已有所有源，然后新增国内源。

```
CODENAME=$(awk -F"=" '/CODENAME/{print $2}' /etc/os-release)

test ${CODENAME} == buster && SEC_CODENAME=${CODENAME} || SEC_CODENAME=${CODENAME}-security

sed -i 's/^/#/g' /etc/apt/sources.list /etc/apt/sources.list.d/*.list

cat > /etc/apt/sources.list.d/tuna.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME} main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security/ ${SEC_CODENAME}  main contrib non-free 
EOF

```


## 下载 **bilibili.sh** 到本地

复制执行

```
curl https://gitee.com/msvr/bilibili-pull/raw/gitee/bilibili.sh | bash -
```

或者下载bilibili.sh后再执行

```
bash bilibili.sh
```

## 执行安装

在B站 `直播中心` > `我的直播间` > `开启直播` 后获得两个参数

- 服务器地址
- 串流密钥

启动安装tui,按要求填入参数，及视频目录路径，将从视频目录搜索mp4文件（不支持子目录）推流

> 先开启直播，再启动推流服务


## 执行脚本

```bash
bash bilibili.sh
```

查看服务运行状态：

```bash
systemctl status bilibili
```

如果服务是 `active (running)` 状态表示正在运行。

```
● bilibili.service
Loaded: loaded (/lib/systemd/system/bilibili.service; static)
Active: active (running) since Thu 2023-11-02 20:10:14 CST; 7s ago
Process: 5158 ExecStartPre=/usr/bin/bash -c ls -1 *.mp4 | xargs -I {} echo -e "file '{}'" >> playli>
Main PID: 5162 (ffmpeg)
Tasks: 1 (limit: 398)
Memory: 61.6M
CPU: 1.618s
CGroup: /system.slice/bilibili.service
└─5162 /usr/bin/ffmpeg -re -threads 2 -stream_loop -1 -safe 0 -f concat -i playlist.txt -...

```


关闭服务

```
systemctl stop bilibili
```

重启服务

```
systemctl restart bilibili
```

允许服务开机启动

```
systemctl enable bilibili
```

注意：短时间内反复重启ffmpeg推流，可能导致推流失败，还有其他失败的原因看log说明

```
journalctl -eu bilibili 
```


# 退出后自动重启



```
mkdir -p /lib/systemd/system/bilibili.service.d
cat > /lib/systemd/system/bilibili.service.d/10-Restart.conf << EOF
[Service]
Restart=on-failure
RestartSec=2s
EOF

systemctl daemon-reload
systemctl restart bilibili

```