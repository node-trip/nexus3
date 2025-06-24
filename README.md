### 📦 Nexus3 Docker Setup Script

Этот скрипт предназначен для **автоматической установки и запуска Nexus3** в Docker-контейнере. Подходит для быстрого развертывания приватного репозитория (Maven, npm, Docker, и др.) с помощью [Sonatype Nexus Repository Manager 3](https://www.sonatype.com/products/repository-oss).

---

### ⚙️ Возможности

- Автоматическое скачивание и запуск Nexus3 в Docker
- Создание необходимых томов и проброс портов
- Поддержка перезапуска контейнера
- Гибкая настройка через переменные

---

### 📥 Установка

Выполните следующую команду в терминале:

```bash
rm -f nexusdocker.sh && wget -nc --no-cache https://raw.githubusercontent.com/node-trip/nexus3/refs/heads/main/nexusdocker.sh && chmod +x nexusdocker.sh && ./nexusdocker.sh
```

---

### 🐳 Требования

- Установленный **Docker**
- Порты **8081**, **5000**, **5001** не должны быть заняты

---

### 🔧 Переменные окружения (опционально)

Вы можете задать переменные перед запуском скрипта, чтобы изменить поведение:

| Переменная      | Описание                        | Значение по умолчанию |
|------------------|----------------------------------|------------------------|
| `NEXUS_PORT`     | Порт для веб-интерфейса Nexus   | `8081`                 |
| `NEXUS_VOLUME`   | Путь для хранения данных        | `~/nexus-data`         |
| `CONTAINER_NAME` | Имя Docker-контейнера           | `nexus3`               |

Пример:

```bash
NEXUS_PORT=9090 CONTAINER_NAME=my_nexus ./nexusdocker.sh
```

---

### 🛠 После установки

1. Перейдите в браузере по адресу: [http://localhost:8081](http://localhost:8081)
2. Войдите в админ-панель:
   - Пользователь: `admin`
   - Пароль: находится в контейнере, получить можно командой:

```bash
docker exec -it nexus3 cat /nexus-data/admin.password
```

---

### 🧹 Удаление

Чтобы остановить и удалить Nexus:

```bash
docker stop nexus3 && docker rm nexus3
```