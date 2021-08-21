# 参考: https://github.com/tohutohu/isucon9/blob/master/Makefile

SHELL = bash

export GO111MODULE=on
# DB_HOST:=127.0.0.1
DB_HOST:=192.168.0.13 # server3
DB_PORT:=3306

### TODO ###
DB_USER:=isucon
DB_PASS:=isucon
DB_NAME:=isucondition

# systemctl start SERVICE_NAME.service ができるように
SERVICE_NAME:=isucondition.go
# API_SERVICE_NAME:=

# git init したディレクトリ
PROJECT_ROOT:=/home/isucon/webapp

# アプリケーションのビルド先が $(BUILD_DIR)/$(BIN_NAME) になるように
BUILD_DIR:=/home/isucon/webapp/go
BIN_NAME:=isucondition

# Nginx
NGX_LOG:=/var/log/nginx/access.log
NGX_PATH:=/etc/nginx

# Envoy
ENVOY_LOG:=/var/log/envoy/access.log

# Git
GIT_REMOTE_URL:=git@github.com:cat-neko-nya/2021quals.git

# MySQL
MYSQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)
MYSQL_LOG:=/tmp/slow-query.log

# kataru
KATARU_CFG:=./kataribe.toml

DISCORDCAT:=/usr/local/bin/discord.sh
DISCORDTEXT := $(DISCORDCAT) --text # $(DISCORDTEXT) "text"
DISCORDCODE := perl -pe 's/\n/\\n/g' | /usr/local/bin/discord.sh --text "$$(RESULTS=$$(cat -); echo -e $${RESULTS:0:1900} | echo "\`\`\`$$(cat -)\`\`\`" | jq -Rs . | cut -c 2- | rev | cut -c 2- | rev)" # command | $(DISCORDCODE)
DISCORDFILE := $(DISCORDCAT) --file # $(DISCORDFILE) filename

PPROF_CMD:=go tool pprof -png -output /tmp/pprof.png
PPROF_PATH:=http://localhost:6060/debug/pprof/profile
PPROF:=$(PPROF_CMD) $(PPROF_PATH)
PPROF_PATH_BENCH:=http://localhost:6061/debug/pprof/profile
PPROF_BENCH:=$(PPROF_CMD) $(PPROF_PATH_BENCH)

CA:=-o /dev/null -s -w "%{http_code}\n"

all: build

.PHONY: clean
clean:
	cd $(BUILD_DIR); \
	rm -rf $(BIN_NAME)

deps:
	cd $(BUILD_DIR); \
	go mod download

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o isucondition

# 各種リスタート

.PHONY: restart
restart: restart-web

.PHONY: restart-web
restart:
	sudo systemctl restart $(SERVICE_NAME).service

# .PHONY: restart-api
# restart-api:
# 	sudo systemctl restart $(API_SERVICE_NAME).service

.PHONY: restart-nginx
restart-nginx:
	sudo systemctl restart nginx.service

.PHONY: restart-mysql
restart-mysql:
	sudo systemctl restart mysql.service

.PHONY: restart-envoy
restart-envoy:
	sudo systemctl restart envoy

.PHONY: test
test:
	curl localhost $(CA)

# MYSQLログイン
.PHOYNY: mysql
mysql:
	$(MYSQL_CMD)

# MYSQLスキーマ初期化
.PHONY: initialize-mysql-schema
initialize-mysql-schema:
	$(MYSQL_CMD) < $(PROJECT_ROOT)/sql/0_Schema.sql

# MySQL(^8.0.21) Redoログ無効化
.PHONY: mysql-disable-redolog
mysql-disable-redolog:
	${MYSQL_CMD} -e'ALTER INSTANCE DISABLE INNODB REDO_LOG'

# 実行して準備 (下の行はmysqlなしの場合)
.PHONY: bench-dev
# bench-dev: echo-bench pull-force before slow-on initialize-mysql-schema dev
bench-dev: echo-bench pull-force before initialize-mysql-schema dev

# ベンチの準備 (下の行はmysqlなしの場合)
.PHONY: bench
# bench: echo-bench pull-force before slow-on initialize-mysql-schema build restart log
bench: echo-bench pull-force before initialize-mysql-schema build restart log

# ベンチの準備 (pull-force せずにその時点のコードを反映) (下の行はmysqlなしの場合)
.PHONY: bench-local
# bench-local: echo-bench before slow-on initialize-mysql-schema build restart log
bench-local: echo-bench before initialize-mysql-schema build restart log

# ベンチの準備 (logの代わりにtop) (下の行はmysqlなしの場合)
.PHONY: bench-top
# bench-top: echo-bench pull-force before slow-on initialize-mysql-schema build restart top
bench-top: echo-bench pull-force before initialize-mysql-schema build restart top

# 最終ベンチ (ログの無効) (下の行はmysqlなしの場合)
.PHONY: bench-fin
# bench-fin: echo-bench pull-force before slow-off initialize-mysql-schema build restart
bench-fin: echo-bench pull-force before initialize-mysql-schema build restart

# ログ出力はなしでベンチの準備
.PHONY: bench-no-log
bench-no-log: echo-bench pull-force before build restart

.PHONY: bench-failed
bench-failed:
	git commit --allow-empty -m "bench (failed) :x:"
	git push

# DBで遅いクエリ, nginxへの遅いリクエストを出力
.PHONY: analyze
analyze: slow alp

# systemdを使わずにそのまま実行
.PHONY: dev
dev: build
	cd $(BUILD_DIR); \
	./$(BIN_NAME)

.PHONY: neko
neko:
	$(DISCORDTEXT) "にゃーん"

.PHONY: echo-bench
echo-bench:
	$(DISCORDTEXT) ":bangbang: benchを投げますにゃ"

.PHONY: score
score:
	cd $(PROJECT_ROOT)
	git add .
	echo; echo -n "score?: "; \
	read score; \
	$(DISCORDTEXT) ":white_check_mark: $$score 点が出ましたにゃ\`\`\`$$(git rev-parse HEAD | cut -c -7)($$(git name-rev --name-only HEAD))\n$$(git log --format=%B --max-count=1 HEAD)\`\`\`"; \
	git commit --allow-empty -m "bench (score: $$score) :white_check_mark:"; \
	git push;

.PHONY: pull-force
pull-force:
	cd $(PROJECT_ROOT); \
	git fetch --all; \
	git reset --hard origin/main

.PHONY: git-init
git-init:
	cd $(PROJECT_ROOT); \
	git init; \
	git remote add origin $(GIT_REMOTE_URL)
	git add -A; \
	git commit -m "init"; \
	git push -u origin main

.PHONY: before
before:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
#	@if [ -f $(NGX_LOG) ]; then \
#		sudo mv -f $(NGX_LOG) ~/logs/$(when)/ ; \
#	fi
	@if [ -f $(MYSQL_LOG) ]; then \
		sudo mv -f $(MYSQL_LOG) ~/logs/$(when)/ ; \
	fi
	rm -r ../images
	cp -r ../init_images ../images
# sudo systemctl restart mysql
	sudo systemctl restart nginx

# systemctlのログを表示
.PHONY: log
log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f

# systemctlのログを表示 (full)
.PHONY: llog
llog:
	sudo journalctl -u $(SERVICE_NAME) -e

# systemctlのログを表示
.PHONY: log-api
log-api:
	sudo journalctl -u $(API_SERVICE_NAME) -n10 -f

# systemctlのログを表示 (full)
.PHONY: llog-api
llog-api:
	sudo journalctl -u $(API_SERVICE_NAME) -e

# pt-query-digest の結果をDiscordに投げる
.PHONY: slow
slow:
	sudo pt-query-digest $(MYSQL_LOG) > /tmp/query-digest.log
	$(DISCORDFILE) /tmp/query-digest.log

# kataribe のログをDiscordに投げる
.PHONY: kataru
kataru:
	sudo cat $(NGX_LOG) | kataribe -f ./kataribe.toml > /tmp/kataribe.log
	cat /tmp/kataribe.log | grep -nE "TOP [0-9]+ Slow Requests" | cut -f1 -d: | expr $$(cat -) - 1 | sed "1,$$(cat -)d" /tmp/kataribe.log | $(DISCORDCODE)
	$(DISCORDFILE) /tmp/kataribe.log

# alp
.PHONY: alp
alp:
	alp ltsv --file=$(NGX_LOG) -m /api/condition/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12},/api/isu/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/icon,/api/isu/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/graph,/api/isu/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/condition,/api/isu/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} --dump /tmp/dump.log --pos /tmp/alp.pos
	alp json --load /tmp/dump.log --sort=avg -r -o count,method,uri,avg  | head -n 20 | ${DISCORDCODE}
	alp json --load /tmp/dump.log --sort=count -r -o count,method,uri,avg  | head -n 20 | ${DISCORDCODE}
	alp json --load /tmp/dump.log --sort=sum -r -o count,method,uri,sum  | head -n 20 | ${DISCORDCODE}

# pprof のログをDiscordに投げる
.PHONY: pprof
pprof:
	$(PPROF)
	$(DISCORDFILE) /tmp/pprof.png

.PHONY: pprof-bench
pprof-bench:
	$(PPROF_BENCH)
	$(DISCORDFILE) /tmp/pprof.png

.PHONY: myprofiler
myprofiler:
	myprofiler -user=$(DB_USER) -password=$(DB_PASSWORD)

.PHONY: slow-on
slow-on:
	sudo mysql -e "set global slow_query_log_file = '$(MYSQL_LOG)'; set global long_query_time = 0; set global slow_query_log = ON;"

.PHONY: slow-off
slow-off:
	sudo mysql -e "set global slow_query_log = OFF;"

.PHONY: install-netdata
install-netdata:
	bash <(curl -Ss https://my-netdata.io/kickstart.sh)

.PHONY: uninstall-netdata
uninstall-netdata:
	wget https://raw.githubusercontent.com/netdata/netdata/master/packaging/installer/netdata-uninstaller.sh
	sudo chmod +x ./netdata-uninstaller.sh
	./netdata-uninstaller.sh --yes --env /etc/netdata/.environment

.PHONY: discord-test
discord-test:
	w | $(DISCORDCODE)

# Nginxの設定ファイルを取り込み
.PHONY: nginx-conf
nginx-conf:
	sudo cp -r ${NGX_PATH}/ ./config
	sudo chmod -R 755 ./config/nginx
	sudo rm -rf ${NGX_PATH}
	sudo ln -s ${PROJECT_ROOT}/config/nginx ${NGX_PATH}

.PHONY: deploy-git-hooks
deploy-git-hooks:
	ln -s ${PROJECT_ROOT}/post-checkout .git/hooks/post-checkout
	chmod +x ./post-checkout

.PHONY: setup
setup:
	sudo apt install -y percona-toolkit dstat git unzip snapd jq graphviz
	# kataribe
	wget https://github.com/matsuu/kataribe/releases/download/v0.4.1/kataribe-v0.4.1_linux_amd64.zip -O kataribe.zip
	unzip -o kataribe.zip
	sudo mv kataribe /usr/local/bin/
	sudo chmod +x /usr/local/bin/kataribe
	rm LICENSE README.md kataribe.zip
	kataribe -generate
	# alp
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.7/alp_linux_amd64.zip -O alp.zip
	unzip -o alp.zip
	sudo mv alp /usr/local/bin/
	sudo chmod +x /usr/local/bin/alp
	rm alp.zip
	# myprofiler
	wget https://github.com/KLab/myprofiler/releases/download/0.2/myprofiler.linux_amd64.tar.gz
	tar xf myprofiler.linux_amd64.tar.gz
	rm myprofiler.linux_amd64.tar.gz
	sudo mv myprofiler /usr/local/bin/
	sudo chmod +x /usr/local/bin/myprofiler
	# discord
	wget https://raw.githubusercontent.com/ChaoticWeg/discord.sh/master/discord.sh
	chmod +x discord.sh
	sudo mv discord.sh /usr/local/bin/
	# kill apparmor
	sudo systemctl stop apparmor
	sudo apt-get purge -y apparmor
	# config files
	wget https://raw.githubusercontent.com/cat-neko-nya/ISUCON-setup/master/.bashrc_
	wget https://raw.githubusercontent.com/cat-neko-nya/ISUCON-setup/master/.inputrc
	wget https://raw.githubusercontent.com/cat-neko-nya/ISUCON-setup/master/.gitconfig
	wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh -O .git-prompt.sh
	mv .inputrc .bashrc_ .gitconfig .git-prompt.sh ~/
	echo "[ -f ~/.bashrc ] && source ~/.bashrc" >> ~/.bash_profile
	echo "[ -f ~/.bashrc_ ] && source ~/.bashrc_" >> ~/.bash_profile