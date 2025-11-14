# Форматирование кода перед merge

## Быстрый способ - одна команда:

```bash
mix format
git add .
git commit -m "chore: auto-format code with mix format"
git push
```

## Если у вас Docker:

```bash
docker-compose run app mix format
git add .
git commit -m "chore: auto-format code with mix format"
git push
```

## Или через make (если есть в Makefile):

```bash
make format
git add .
git commit -m "chore: auto-format code with mix format"
git push
```

## После форматирования:

Все файлы будут автоматически приведены к стандарту Elixir formatter.
Затем можно будет делать merge в master без проблем с CI.

## Файлы, которые нужно отформатировать:

Список файлов был предоставлен в сообщении об ошибке CI.
`mix format` автоматически обработает их все.
