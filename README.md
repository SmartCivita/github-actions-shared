# GitHub Actions Shared

Repositorio centralizado para workflows y acciones reutilizables de GitHub Actions.

## Contenido

### Workflows Reutilizables

#### `auto-commit-message.yml`
Corrige automáticamente mensajes de commit que no siguen el formato Conventional Commits.

**Trigger:** `workflow_call`

**Secrets requeridos:**
- `PERSONAL_ACCESS_TOKEN` - Token para push forzado
- `OPENCODE_API_KEY` - API key para generación de mensajes
- `DISCORD_WEBHOOK` - Webhook para notificaciones

**Uso desde otro repositorio:**
```yaml
jobs:
  call-auto-commit:
    uses: SmartCivita/github-actions-shared/.github/workflows/auto-commit-message.yml@main
    secrets:
      PERSONAL_ACCESS_TOKEN: ${{ secrets.PERSONAL_ACCESS_TOKEN }}
      OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
      DISCORD_WEBHOOK: ${{ secrets.DISCORD_WEBHOOK }}
```

#### `auto-pr-description.yml`
Genera automáticamente título y descripción de PRs usando IA.

**Trigger:** `workflow_call`

**Inputs:**
- `target-branch` (string, default: `main`) - Rama base del PR

**Secrets requeridos:**
- `PERSONAL_ACCESS_TOKEN` - Token para operaciones Git
- `OPENCODE_API_KEY` - API key para generación
- `DISCORD_WEBHOOK` - Webhook para notificaciones

**Uso desde otro repositorio:**
```yaml
jobs:
  call-auto-pr:
    uses: SmartCivita/github-actions-shared/.github/workflows/auto-pr-description.yml@main
    secrets:
      PERSONAL_ACCESS_TOKEN: ${{ secrets.PERSONAL_ACCESS_TOKEN }}
      OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}
      DISCORD_WEBHOOK: ${{ secrets.DISCORD_WEBHOOK }}
    with:
      target-branch: main
```

### Acciones Compuestas

#### `discord-notify`
Envía notificaciones a Discord con formato embebido.

**Inputs:**
- `title` (required) - Título de la notificación
- `webhook` (required) - Webhook de Discord
- `color` (default: `5763719`) - Color del embed
- `description` - Descripción adicional
- `url` - URL para el título
- `event-type` - Tipo de evento (commit, pr, ci, etc.)
- `old-msg` - Mensaje anterior
- `new-msg` - Mensaje nuevo
- `commit-sha` - SHA del commit
- `pr-number` - Número del PR
- `status` - Estado (success, skipped, failure)
- `run-url` - URL del workflow

## Secrets Requeridos

Para usar estos workflows, necesitas configurar estos secrets en cada repositorio:

| Secret | Descripción |
|--------|-------------|
| `PERSONAL_ACCESS_TOKEN` | GitHub PAT con permisos `repo` |
| `OPENCODE_API_KEY` | API key de opencode.ai |
| `DISCORD_WEBHOOK` | Webhook de Discord para notificaciones |

## Estructura del Repositorio

```
.github/
├── actions/
│   └── discord-notify/
│       ├── action.yml        # Metadata de la acción
│       └── discord-notify.sh # Script de notificación
└── workflows/
    ├── auto-commit-message.yml  # Workflow reutilizable
    └── auto-pr-description.yml   # Workflow reutilizable
```

## Actualización

Los workflows usan `@main` para seguir la rama principal. Para actualizaciones controladas, considera usar tags (ej: `@v1`).

## Notas

- El repositorio debe ser **público** para que funcione el `workflow_call` entre organizaciones
- Los workflows mantienen sus propios triggers (`push`, `pull_request`) además del `workflow_call`
- Las notificaciones solo se envían en caso de éxito

## Links

- [Documentación de Reusable Workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Metadata de Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax)