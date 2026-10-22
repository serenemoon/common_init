# 通用命令入口：make <分组>-<动作>
#
# 直接运行 make 或 make help 会按分组列出全部命令。
#
# 新增命令的约定
#   1. 目标名用「分组-动作」，例如 git-aliases、nvim-conf
#   2. 在 help 的对应分组下加一行说明（还没有这个分组就新起一段）
#   3. 命令要幂等，重复执行结果一致
#   4. 把新目标加进 .PHONY
#
# 输出文案用英文：make 是原生程序，在 Windows 控制台按 ANSI 代码页输出，中文会乱码。
# 注释和文档照旧用中文。

.DEFAULT_GOAL := help
.PHONY: help git-aliases

# ---------------------------------------------------------------- 帮助

help:
	@echo 'Usage: make <target>'
	@echo
	@echo 'git:'
	@echo '  git-aliases   Set common git aliases (list in README)'

# ---------------------------------------------------------------- git

git-aliases:
	@git config --global alias.st status
	@git config --global alias.co checkout
	@git config --global alias.br branch
	@git config --global alias.cb "checkout -b"
	@git config --global alias.cm commit
	@git config --global alias.cma "commit --amend"
	@git config --global alias.cme "commit --amend --no-edit"
	@git config --global alias.aa "add --all"
	@git config --global alias.cp cherry-pick
	@git config --global alias.cl "clean -f -d"
	@git config --global alias.pr "pull --rebase"
	@git config --global alias.rsh "reset --hard HEAD"
	@git config --global alias.rsh1 "reset --hard HEAD~"
	@git config --global alias.dfh "diff HEAD"
	@git config --global alias.dfhs "diff HEAD --stat"
	@git config --global alias.df "diff HEAD~1"
	@git config --global alias.dfs "diff HEAD~1 --stat"
	@git config --global alias.lg "log --oneline --graph --decorate --all"
	@git config --global alias.ll "log --oneline -20"
	@git config --global alias.logs "log --stat"
	@git config --global alias.logf "log --format=fuller"
	@git config --global alias.rl reflog
	@git config --global alias.rlf "reflog --pretty=fuller"
	@echo 'Configured git aliases: st co br cb cm cma cme aa cp cl pr rsh rsh1 dfh dfhs df dfs lg ll logs logf rl rlf'
