# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EzNews is a multilingual news simplification platform built with Phoenix LiveView and Ash Framework. It processes Estonian news articles and simplifies them for language learners at different proficiency levels (A1, A2, B1). The application fetches news from RSS feeds, uses AI to simplify content, and provides multilingual support with vocabulary learning features.

## Custom Agents

### General Proposal Agent

The project includes a custom `general-proposal` agent for executing any development tasks with full access to skills.

**Location**: `.claude/agents/general-proposal.md`

**Purpose**: Universal task executor that can handle any development work by leveraging all available skills and tools.

**Usage**:
```
# Explicit invocation
> Use the general-proposal agent to [task description]

# Automatic delegation (Claude decides when to use)
> [Describe your task and Claude may automatically delegate to the agent]
```

**Capabilities**:
- Full access to all custom skills in `.claude/skills/`
- Backend development (Elixir, Phoenix, GenServers)
- Database operations (migrations, schemas, TimescaleDB)
- Frontend development (LiveView, JavaScript)
- API integrations and testing
- DevOps tasks

**Model**: Sonnet 4.5 (claude-sonnet-4-5-20250929)

## Custom Skills

Skills are stored in `.claude/skills/` directory. See `SKILLS_GUIDE.md` and `.claude/skills/README.md` for details on creating and using skills.

**Current Skills**:
- `example-skill` - Template for creating new skills

**Planned Skills**:
- `elixir-genserver` - Generate GenServer modules with tests
- `phoenix-liveview` - Create LiveView components
- `db-migration` - Database migration generator
- `binance-test` - Binance API test helpers

## Development Workflow

1. Use `/agents` command to manage custom agents
2. Invoke skills with `> Use [skill-name] skill for [task]`
3. Let the general-proposal agent handle complex multi-step tasks
4. Skills and agents work together to streamline development

## Key Directories

- `.claude/agents/` - Custom agent definitions
- `.claude/skills/` - Custom skill definitions
- Project uses umbrella structure with `apps/` directory

See project documentation for full development setup and commands.
