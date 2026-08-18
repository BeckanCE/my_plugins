# Skeet Database — Guía de uso

## 1. Comandos

| `sm_skeets` | Muestra tu cantidad de skeets y tu posición en el ranking |
| `sm_top5` | Muestra un panel con el Top 5 de skeeters del servidor |
| `sm_skeet_sql_status` | `ADMFLAG_GENERIC` | Muestra el estado de la conexion, tabla y SQL (MySQL/SQLite) |
| `sm_skeet_migrate_to_sql` | `ADMFLAG_ROOT` | Muestra qué va a hacer. 1ro|
| `sm_skeet_migrate_to_sql CONFIRM` | `ADMFLAG_ROOT` | Importa los datos de skeet_database.txt a SQL. 2do|

## 2. ConVars (Default)

| `skeet_database_enable` | `1` | Activa/desactiva el plugin completo |
| `skeet_database_announce_oneshot` | `1` | Solo cuenta como skeet si el Hunter murió de **un solo disparo** |
| `skeet_database_announce` | `0` | Anuncia en el chat cada skeet/deadstop |
| `skeet_database_modes_tog` | `4` | En qué modos corre: `0`=Todos, `1`=Coop, `2`=Survival, `4`=Versus (se suman) |
| `top_skeet_survivors_required` | `4` | Mínimo de supervivientes conectados para activar el plugin |
| `skeet_database_ai_hunter_enable` | `1` | ¿Cuenta skeets a Hunters controlados por IA? |
| `skeet_database_1v1_seprate` | `1` | Lleva un ranking separado para partidas 1v1 (1 superviviente vs 1 infectado) |
| `skeet_database_use_sql` | `0` | `1` = usar MySQL/SQLite. `0` = usar 'skeet_database.txt'|
| `skeet_database_sql_config` | `skeet_db` | Nombre del bloque en `databases.cfg` |

⚠️ El valor de `skeet_database_sql_config` tiene que coincidir **exactamente** (mayúsculas/minúsculas y guiones incluidos) con el nombre del bloque en `databases.cfg`, o la conexión falla silenciosamente (revisar con `sm_skeet_sql_status`).


## 3. Configurar `databases.cfg`

Agregar un bloque con el mismo nombre que pusiste en `skeet_database_sql_config`, dentro de addons/sourcemod/configs/databases.cfg

"skeet_db"   // debe coincidir con skeet_database_sql_config
{
    "driver"    "default"
    "host"      "TU_HOST"
    "database"  "TU_BASE"
    "user"      "TU_USUARIO"
    "pass"      "TU_PASSWORD"
    "port"      "3306"
}

Para usar SQLite en vez de MySQL (no requiere servidor externo, se autogenera el archivo):

"skeetdb"
{
    "driver"    "sqlite"
    "database"  "skeet_stats"
}

**Requisito importante:** la cuenta de MySQL necesita permiso `CREATE TABLE`, no solo `SELECT`/`INSERT`/`UPDATE` — el plugin crea la tabla `skeet_stats` solo, la primera vez que conecta. Ver detalle exacto de permisos en el punto 4.

## 4. Permisos de MySQL necesarios

El usuario de la base de datos MySQL debe contar con los siguientes permisos básicos:

GRANT SELECT, INSERT, UPDATE, CREATE ON tu_base_de_datos.* TO 'tu_usuario'@'%';
FLUSH PRIVILEGES;

## 5. Importar datos de skeets de skeet_database.txt a MySQL/SQLite

Ejecutalo si necesitas pasar los datos locales a SQL

1. Activar SQL y confirmar conexión:
   ```
   skeet_database_use_sql "1"
   sm_skeet_sql_status
   ```
   Tiene que decir `Conectado: Si | Tabla 'skeet_stats' existe: Si`.

2. Si tienes datos locales en el modo 1v1 separado, asegurate de tener `skeet_database_1v1_seprate "1"` activo antes de importalo (si no, ese archivo se salta).

3. Importar los datos:
   ```
   sm_skeet_migrate_to_sql            // muestra el aviso
   sm_skeet_migrate_to_sql CONFIRM    // inicia el importe
   ```

4. El resultado aparece en consola/log unos segundos después:
   ```
   [Skeet] Importacion completa: 47/47 filas OK, 0 fallidas.
   ```

Correr el comando dos veces no duplica ni resta datos.

## 6. Consultar los datos directamente (MySQL Workbench u otro cliente)
Si deseas hacer consultas manuales a la tabla skeet_stats desde un cliente como MySQL Workbench o PhpMyAdmin:

-- Consultar el Top 5 global
SELECT name, skeets FROM skeet_stats
WHERE is_1v1 = 0 AND skeets > 0
ORDER BY skeets DESC LIMIT 5;

-- Buscar las estadísticas de un jugador por SteamID
SELECT * FROM skeet_stats WHERE steamid = 'STEAM_1:1:57051684';

-- Obtener el total de skeets registrados por modo
SELECT is_1v1, SUM(skeets) AS total_skeets, COUNT(*) AS total_jugadores
FROM skeet_stats GROUP BY is_1v1;

## 7. Cosas a tener en cuenta

- **Ranking único y sincronizado**: Si usas una base de datos MySQL compartida en varios servidores, el ranking de los jugadores se acumulará de forma global.
- **Actualización de Nombre**: El nombre del jugador guarado en la base de datos se actualiza automáticamente cada vez que el jugador registra un nuevo skeet.
- **Compatibilidad**: En cualquier momento puedes cambiar `skeet_database_use_sql` a `0` para volver al guardado local en `skeet_database.txt`.