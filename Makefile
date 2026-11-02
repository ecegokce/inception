COMPOSE_FILE = srcs/docker-compose.yml
ENV_FILE     = srcs/.env
COMPOSE      = docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE)

DATA_DIR     = /home/egokce/data
SECRETS_DIR  = secrets

SECRET_NAMES = db_password db_root_password wp_admin_password wp_user_password

.PHONY: all init build up down stop clean fclean re logs ps check-config

# Creates srcs/.env and secrets/ on the VM, if they don't already exist.
# Both are git-ignored, so a fresh `git clone` never has them: this target
# is what turns the cloned repo into something `make all` can actually run.
init:
	@test -f $(ENV_FILE) || cp srcs/.env.example $(ENV_FILE)
	@mkdir -p $(SECRETS_DIR)
	@for name in $(SECRET_NAMES); do \
		file=$(SECRETS_DIR)/$$name.txt; \
		if [ ! -f $$file ]; then \
			openssl rand -base64 24 > $$file; \
			chmod 600 $$file; \
			echo "generated $$file"; \
		else \
			echo "$$file already exists, leaving it untouched"; \
		fi; \
	done
	@echo "init done: edit $(ENV_FILE) if needed, secrets are in $(SECRETS_DIR)/"

# Fails loudly instead of letting docker compose run with a missing
# secrets/.env and produce a confusing error later.
check-config:
	@test -d $(SECRETS_DIR) && test -f $(ENV_FILE) || \
		(echo "error: missing $(SECRETS_DIR)/ or $(ENV_FILE) - run 'make init' first" && exit 1)

all: check-config
	mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	$(COMPOSE) up -d --build

build: check-config
	$(COMPOSE) build

up: check-config
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

# Removes containers/images built by this project, keeps volumes and data.
clean: down
	$(COMPOSE) down --rmi local

# Also wipes the named volumes and the data they're backed by on the host.
# Host data lives under /home/egokce/data (root-owned by containers), so
# this usually needs sudo.
fclean: clean
	$(COMPOSE) down -v
	rm -rf $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

re: fclean all
