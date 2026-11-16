.DEFAULT_GOAL := all

COMPOSE_FILE = srcs/docker-compose.yml
ENV_FILE     = srcs/.env
COMPOSE      = docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE)

DATA_DIR     = /home/egokce/data
SECRETS_DIR  = secrets

SECRET_NAMES = db_password db_root_password wp_admin_password wp_user_password

.PHONY: all build up down start stop clean fclean re logs ps check-config

check-config:
	@test -d $(SECRETS_DIR) && test -f $(ENV_FILE) || \
		(echo "error: missing $(SECRETS_DIR)/ or $(ENV_FILE)" && exit 1)

all: check-config
	mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	$(COMPOSE) up -d --build --force-recreate

build: check-config
	$(COMPOSE) build

up: check-config
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

start: check-config
	$(COMPOSE) start

stop:
	$(COMPOSE) stop

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean: down
	$(COMPOSE) down --rmi local

fclean: clean
	$(COMPOSE) down -v
	sudo rm -rf $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

re: fclean all
