---
name: example-skill
description: Пример skill файла для демонстрации формата
tags: example, template
---

# Пример Skill

Это пример skill файла. Замените его содержимое на реальные skills из вашего архива.

## Формат Skill файла

### Frontmatter (обязательно)
```yaml
---
name: skill-name              # Уникальное имя (kebab-case)
description: Short description # Краткое описание
tags: tag1, tag2              # Теги (опционально)
---
```

### Содержимое

После frontmatter идут инструкции для Claude Code на естественном языке или Markdown.

## Использование

В Claude Code:
```
/skill example-skill
```

## Ваши действия

1. Удалите этот файл: `rm /home/user/test/.claude/skills/example-skill.md`
2. Распакуйте ваш архив со skills в эту директорию
3. Закоммитьте изменения в git
