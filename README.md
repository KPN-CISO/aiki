# 合氣 notes

## code patches

Two patches were needed to make the ssh daemon work with all the buggy 
brute force clients (and IoT) devices out there.

The first was a patch to server.go, because ssh brute force clients surprisingly do not respect the maxTries option:

```diff
 	sessionID := s.transport.getSessionID()
 	var cache pubKeyCache
 	var perms *Permissions
+	// addition to break after maxTries
+	var count = 0
+	const maxTries = 3
 
 userAuthLoop:
 	for {
@@ -305,6 +308,12 @@ userAuthLoop:
 			}
 
 			perms, authErr = config.PasswordCallback(s, password)
+			// addition to break after maxTries
+			if count >= maxTries {
+				authErr = errors.New("ssh: maxTries reached")
+				break
+			}
+			count += 1
 		case "keyboard-interactive":
 			if config.KeyboardInteractiveCallback == nil {
 				authErr = errors.New("ssh: keyboard-interactive auth not configubred")
```


The other was a patch the ssh client in go, because ubiquity devices run with terribly bad cypher suites:

```diff
 var supportedCiphers = []string{
 	"aes128-ctr", "aes192-ctr", "aes256-ctr",
 	"aes128-gcm@openssh.com",
-	"arcfour256", "arcfour128",
+	"arcfour256", "arcfour128", "aes128-cbc",
 }
 
```

## running aiki

```bash
./aiki-linux-amd64
```

or

```bash
go run aiki.go
```

You will probably want to run this as an unprivileged process (I just did it YOLO-style as root on some DigitalOcean instances):

```bash
sysctl -w net.ipv4.conf.eth0.route_localnet=1
iptables -t nat -I PREROUTING -p tcp --dport 22 -j DNAT --to 127.0.0.1:2222
iptables -t nat -A OUTPUT -p tcp -o lo --dport 22 -j REDIRECT --to-ports 2222
```

## running into "too many open files"

Once I managed to get my daemon working in non-blocking Listen mode,
another problem revealed itself: "*too many open files*" was killing all
my instances. I figured it had to do with sloppy coding. And it did.
However, fixing that bug (`go func(tcpConn net.Conn) {...}(tcpConn)`, not `go func() {...}()`)
actually seemed to aggravate the issue.

So, for a running instance, I did:

```bash
cat /proc/$(pgrep -f aiki-linux-amd64)/limits |\
egrep 'Limit|files'

Limit               Soft Limit  Hard Limit     Units
Max open files      1024        65536          files
```

1024 was not going to cut it with some of these bots.
https://easyengine.io/tutorials/linux/increase-open-files-limit/ gave
some good examples of how to fix this issue.

```bash
# cat /proc/sys/fs/file-max
48216
# vim /etc/sysctl.conf
# sysctl -p
fs.file-max = 2097152
# cat /proc/sys/fs/file-max
2097152
```

Then for the soft limits, add this:

```bash
⠠⠵ grep -v ^# /etc/security/limits.conf

*         hard    nofile      500000
*         soft    nofile      500000
root      hard    nofile      500000
root      soft    nofile      500000
```

### checking

```bash
⠠⠵ for i in 1 2 3 4 5 6; do echo $i && ssh trap${i} \
'grep fs.file-max /etc/sysctl.conf';done
1
fs.file-max = 2097152
2
fs.file-max = 2097152
3
fs.file-max = 2097152
4
fs.file-max = 2097152
5
fs.file-max = 2097152
6
fs.file-max = 2097152

⠠⠵ for i in 1 2 3 4 5 6; do echo $i && ssh trap${i}\
'grep ^root /etc/security/limits.conf';done
1
root      hard    nofile      500000
root      soft    nofile      500000
2
root      hard    nofile      500000
root      soft    nofile      500000
3
root      hard    nofile      500000
root      soft    nofile      500000
4
root      hard    nofile      500000
root      soft    nofile      500000
5
root      hard    nofile      500000
root      soft    nofile      500000
6
root      hard    nofile      500000
root      soft    nofile      500000

⠠⠵ for i in 1 2 3 4 5 6; do echo $i && ssh trap${i}\
'ulimit -n';done
1
500000
2
500000
3
500000
4
500000
5
500000
6
500000

```


## creating aiki.log

```bash
tail --retry --follow=name -F /var/log/syslog | grep --line-buffered aiki >> aiki.log
```


## get status updates

*status.sh*

```bash
for i in {1..6}; do
echo "#vv  trap${i}"
ssh trap${i} ./currentstate.sh
echo "#^^  trap${i}"
done
```

*currentstate.sh*

```bash
#!/usr/bin/env bash
hostname
ls -halF ~/aiki.log
# ss -t |fgrep :2222
[[ ! -z "$(pgrep -f ./aiki-linux-amd64)" ]] && lsof -c aiki -n -iTCP -sTCP:LISTEN
# [[ ! -z "$(pgrep -f ./aiki-linux-amd64)" ]] && lsof -n -T -p $(pgrep -f ./aiki-linux-amd64)
echo "connections:"
ss -son
```

## Disclaimer

This software has been created purely for the purposes of academic research and for the development
of effective defensive techniques, and is not intended to be used to attack systems except where
explicitly authorized. Project maintainers are not responsible or liable for misuse of the software.
Use responsibly.
