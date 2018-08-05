APP = hatoishi_app

.PHONY: all
all: up

.PHONY: bash
bash:
	docker-compose run $(APP) bash

.PHONY: fix_perms
fix_perms:
	sudo chown -R $(USER):$(USER) .

.PHONY: clean
clean: fix_perms
	echo log/*.log | xargs -n1 cp /dev/null

.PHONY: pull
pull:
	docker-compose pull

.PHONY: build
build:
	docker-compose stop
	docker-compose rm -fs
	docker-compose build --force-rm --no-cache --pull

.PHONY: up
up:
	docker-compose up $(APP)

.PHONY: bundle
bundle:
	docker-compose run $(APP) bundle

jekyll:
	docker-compose run $(APP) bundle exec jekyll build

