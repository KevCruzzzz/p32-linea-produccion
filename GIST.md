# 🏭 Línea de producción — Demo UI Erlang/OTP (Proyecto #32)

| | |
|---|---|
| **Alumno** | TU NOMBRE COMPLETO · No. Control TU_NUMERO |
| **Materia** | Programación Lógica y Funcional |
| **Profesor** | René Solís Reyes |
| **Institución** | TecNM / Instituto Tecnológico de Tijuana |
| **Fecha** | 5 de noviembre de 2026 |
| **Proyecto** | #32 Línea de producción (Industria y manufactura) del catálogo [tectijuana/erlang-proyectos](https://github.com/tectijuana/erlang-proyectos) |

### 🔗 Enlaces de la entrega

| Recurso | Enlace |
|---|---|
| 💻 Código fuente | [github.com/TU_USUARIO/p32-linea-produccion](https://github.com/TU_USUARIO/p32-linea-produccion) |
| 🌐 Sistema en vivo (AWS EC2) | [http://TU_IP:8080](http://TU_IP:8080) |
| 📹 Instalación en asciinema | [TU_ENLACE_ASCIINEMA](TU_ENLACE_ASCIINEMA) |
| 🎨 Diseño en Google Stitch | [Ver las pantallas](TU_ENLACE_STITCH) |
| 🎬 Demo en video (Loom) | [Ver demo](TU_ENLACE_LOOM) |

---

## 1. ¿Qué es y para qué sirve?

Es un **monitor y simulador de una línea de producción** de 8 estaciones en serie con buffers de 5 piezas. Muestra en vivo cuántas piezas salen, cuál estación es el **cuello de botella** (que puede moverse), cuánto tiempo se pierde por **paros** y cómo un paro se **propaga**: hacia atrás como *bloqueo* y hacia adelante como *inanición*.

**📸 Panel en vivo funcionando en AWS** (se ve la IP en la barra de direcciones)

![Panel en vivo](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/04-panel.png)

---

## 2. Arquitectura (Erlang/OTP)

```
p32_linea_de_produccion_sup            (rest_for_one)
├── p32_registro        dueño de la tabla ETS: piezas, colas, contadores, bitácora
├── p32_linea_sup       (rest_for_one)  est1, buf1, est2, buf2, ... est8
│   ├── p32_estacion ×8   gen_statem: esperando | procesando | bloqueada | falla
│   └── p32_buffer   ×7   cola acotada (5) entre estación N y N+1
├── p32_linea           foto cada 200 ms + historial -> métricas (solo lee)
└── p32_simulador       escenario del turno + inyección de fallas y caos
cowboy -> p32_http      REST + SSE (/api/stream) + /metrics
```

| Decisión | Caso difícil que resuelve |
|---|---|
| Estado duradero en ETS (`p32_registro`, primer hijo) | Reanudar sin perder ni duplicar piezas |
| Falla como estado; la pieza queda en la estación con su tiempo restante | Pieza a medias |
| Buffers de 5; estación `bloqueada` si no hay lugar | Un paro se propaga hacia atrás sin llenar de más |
| `esperando` separado de `procesando` con tiempos acumulados | Distinguir estación lenta de estación esperando |
| `rest_for_one` en orden de la línea | Reinicio ordenado; el estado no se pierde porque está en ETS |

**¿Por qué Erlang?** Cada estación es un proceso aislado: si una falla, el supervisor la reinicia sin tumbar a las demás ("let it crash").

**Programación funcional aplicada:** el cálculo de métricas (`p32_metricas`) son funciones puras sobre mapas inmutables; el estado de cada estación es un mapa que se transforma en cada transición.

---

## 3. Instalación en AWS Academy (paso a paso)

### 3.1 Crear la máquina virtual

1. **AWS Academy → Learner Lab → Start Lab**, esperar el círculo verde y clic en **AWS**.
2. **EC2 → Lanzar instancia** y configurar:
   - **Nombre:** `linea-produccion`
   - **AMI:** Ubuntu Server 24.04 LTS, **64 bits (Arm)**
   - **Tipo:** `t4g.small`
   - **Par de claves:** `practica-linea` (guardado fuera del repositorio)
   - **Red → Editar:** regla SSH puerto 22 y regla TCP personalizado puerto **8080**, ambas desde `0.0.0.0/0`
   - **Almacenamiento:** 10 GiB
3. **Lanzar instancia** y copiar la **Dirección IPv4 pública**.

**📸 Instancia en ejecución**

![EC2](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/01-aws-ec2.png)

**📸 Reglas del grupo de seguridad**

![Puertos](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/02-security-group.png)

### 3.2 Instalar el sistema (un solo script)

**Conectar → Conexión de la instancia EC2 → Conectar** y ejecutar:

```bash
git clone https://github.com/TU_USUARIO/p32-linea-produccion.git
cd p32-linea-produccion
bash deploy/instalar.sh
```

| Paso | Qué hace |
|---|---|
| 1 | Instala Erlang/OTP y rebar3 con `apt` |
| 2 | `rebar3 compile` (con `warnings_as_errors`) |
| 3 | `rebar3 eunit` (8 pruebas, incluye caos) |
| 4 | `rebar3 release` (release autocontenido) |
| 5 | Lo instala en `/opt/linea32` como **servicio systemd** con usuario propio, sin root |

**📸 `rebar3 eunit` en verde y servicio instalado**

![eunit](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/03-eunit.png)

> Los mensajes `SUPERVISOR REPORT ... reason: killed` durante las pruebas **no son errores**: son las pruebas de caos matando procesos a propósito.

### 3.3 Comprobar el servicio

```bash
uname -m                                       # aarch64
sudo systemctl status linea32 --no-pager       # active (running)
curl -s localhost:8080/metrics
```

---

## 4. Manual de uso del panel

Abrir `http://TU_IP:8080` (con `http://`, no `https`). Funciona también en celular.

1. **Indicadores:** piezas terminadas / 900, piezas por hora (últimos 10 min simulados) contra la meta de 120, capacidad real, WIP, tiempo de ciclo (Ley de Little), estación cuello y paro acumulado.
2. **Línea:** cada tarjeta es una estación: 🟢 procesando · 🔵 esperando (inanición) · 🟠 bloqueada · 🔴 falla. Borde ámbar = **cuello**. Entre tarjetas, los buffers (5 casillas).
3. **▶ Turno 7.5 h:** elige velocidad (×50, ×200 o ×1000) y arranca el escenario: falla de 3 min en E4 a la hora 1 y +20 % de ciclo en E6 a la hora 4.
4. **Paros y ciclos:** `Paro 3 min E4`, `Paro 15 min E4`, `Falta material E1`, `Cambio de modelo +20 % E6`, `E2 se vuelve lenta ×1.6`, `Restablecer ciclos`.
5. **Caos:** elige la estación y `Matar proceso de estación` o `Matar buffer`; `Reparar` termina un paro.
6. **Detalle:** clic en una estación para ver porcentajes de tiempo, pieza actual, reinicios y falla restante.
7. **Bitácora:** eventos en orden (paros, reanudaciones, cambios de ciclo, caos).

**📸 Detalle de una estación**

![Detalle](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/05-detalle.png)

**📸 Diseño en Google Stitch**

![Stitch](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/07-stitch.png)

---

## 5. Resultado del escenario

| Indicador | Valor |
|---|---|
| Piezas terminadas al fin del turno / tras vaciar la línea | 663 / **696** de 900 |
| Paro de E4 | 181 s |
| Cuello | E6 (36 s → 43.2 s tras el cambio de modelo) |
| Capacidad | 100 pzas/h → 83.3 pzas/h (meta del takt: 120) |
| Estimación a mano | ≈ 691 piezas |
| Piezas perdidas o duplicadas | 0 |

**Conclusión:** con un cuello de 36 s la línea no puede cumplir el takt de 30 s.

---

## 6. Pruebas de caos

| Qué se mató / inyectó | Qué esperaba | Qué ocurrió |
|---|---|---|
| Procesos de las estaciones 1, 3, 5, 2, 8, 6 y 4 y del buffer 3 | Reinicio por el supervisor sin perder piezas | `creadas = salidas` al vaciar y sin ids repetidos |
| Paro largo en E8 | Backpressure: buffers hasta 5 y E7 bloqueada | Buffer 7 = 5/5; ninguno pasó de 5 |
| Paro en E4 con pieza a medias | La pieza se conserva | Misma pieza durante el paro y la terminó al reparar |

**📸 Prueba de caos en el panel:** una estación con `Reinicios: 1`.

![Caos](https://github.com/TU_USUARIO/p32-linea-produccion/raw/main/evidencias/06-caos.png)

---

## 7. API

| Método | Ruta | Uso |
|---|---|---|
| GET | `/api/linea` | Estado y métricas |
| GET | `/api/stream` | SSE cada 500 ms |
| GET | `/api/bitacora` | Últimos 100 eventos |
| POST | `/api/simulacion/turno?velocidad=200` | Inicia el turno |
| POST | `/api/estaciones/:id/paro?segundos=180&causa=falla_maquina` | Paro |
| POST | `/api/estaciones/:id/ciclo?factor=1.2` | Cambia el ciclo |
| POST | `/api/estaciones/:id/reparar` | Termina un paro |
| POST | `/api/caos/matar_estacion/:id` · `/api/caos/matar_buffer/:id` | Caos |
| GET | `/metrics` | Formato Prometheus |

Diagnóstico remoto con recon:

```bash
sudo -u linea32 HOME=/opt/linea32 /opt/linea32/bin/p32_linea_de_produccion eval 'recon:proc_count(memory, 3).'
```

---

## 8. Solución de problemas

| Problema | Causa | Solución |
|---|---|---|
| El navegador no abre `IP:8080` | Falta la regla del puerto 8080 | Grupo de seguridad → Reglas de entrada → TCP 8080 desde `0.0.0.0/0` |
| Chrome no abre Stitch | Una extensión bloquea un componente | Abrir en ventana de incógnito |
| La IP cambió | Learner Lab apaga la VM al terminar la sesión | Start Lab → iniciar la instancia y copiar la nueva IP; el servicio arranca solo |
| La regla de SSH quedó como "TCP puerto 0" | Se cambió el tipo de la regla 1 | Regla de tipo **ssh** (22) y otra TCP 8080 |
| *(agrega aquí los problemas que realmente te pasen, con su error y su solución)* | | |

---

## 9. Seguridad de credenciales

- La llave `practica-linea.pem` se guardó solo en mi computadora; no se subió al repositorio ni al gist.
- El servicio corre con un usuario de sistema (`linea32`), sin root.
- No se muestran contraseñas ni tokens en las capturas.
- La cookie de Erlang de `vm.args` es de desarrollo; en producción debe cambiarse.

---

## 10. Supuestos y cifras verificadas

**Supuestos propios:** 1 s simulado = 1000/velocidad ms reales; ciclos base 28, 30, 27, 34, 31, 36, 29 y 32 s con ±10 %; 7 buffers de 5; material infinito hasta el fin del turno; la bitácora vive en ETS (no sobrevive a apagar la VM); OTP 25 de Ubuntu 24.04, por eso hay un codificador JSON propio.

**Cifras verificadas:** takt = 27,000 / 900 = 30 s y 7.5 h × 3600 = 27,000 s (por cálculo). Ley de Little: comprobada con los datos medidos. *(Cifras de contexto del enunciado, como el peso de la manufactura en Tijuana: verificar con fuente vigente antes de citarlas.)*

---

## 11. Reflexión técnica

*(Reescribe esto con tus palabras y con lo que a ti te pasó. Borrador:)*

Lo más difícil fue decidir **dónde vive el estado**. Si la pieza en proceso estuviera solo en el proceso de la estación, matarla perdería la pieza; por eso guardé la pieza, las colas y los tiempos acumulados en ETS, dentro del primer hijo del supervisor. Ahí entendí que en Erlang el orden de los hijos y dónde guardas los datos son decisiones de diseño.

Un error real que tuve: usé `0` como "la falla ya terminó" y la reparación nunca ocurría. Resultó que el reloj monotónico de Erlang puede ser **negativo**, así que `0` quedaba en el futuro. Lo arreglé usando el instante actual. Lo detecté porque una prueba de eunit falló.

También medí algo que el enunciado solo insinúa: con un cuello de 36 s la línea no alcanza el takt de 30 s, y el cambio de modelo en la E6 baja la capacidad de 100 a 83 piezas/h. La estimación a mano (≈691) coincidió con la simulación (696).

---

## Referencias

- Catálogo del curso: https://github.com/tectijuana/erlang-proyectos
- Enunciado del problema #32 (carpeta `problema/` del catálogo)
- Erlang/OTP Design Principles (gen_statem, supervisores): https://www.erlang.org/doc/system/design_principles.html
- Cowboy 2.12: https://ninenines.eu/docs/en/cowboy/2.12/guide/
- recon: https://ferd.github.io/recon/
