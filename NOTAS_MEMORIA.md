# Notas para la memoria final (LCSE: PIC)

Material en bruto para rellenar `LCSE- Plantilla Memoria Final.docx`. Va ordenado según
los apartados de la plantilla. La plantilla pide explicar **cómo** se resolvió cada reto,
no repetir el enunciado. Límite: 10 páginas más las mejoras, en Arial 12.

Última actualización: 24/11/2026 (top de placa propio con USB‑UART y reset con `locked`; `tb_Nexys_PICtop_timing` superado en behavioral).

---

## Tabla "Retos técnicos superados" (estado actual)

| Reto | Estado | Evidencia |
|---|---|---|
| RS‑232 + DMA + RAM | **SÍ** | `tb_DMA_RX` con 0 errores (24/10), prueba en placa con `Nexys_PICtop2` (24/10) y `tb_Terna` con el interbloqueo corregido, 8 casos y 0 errores (23/11) |
| ALU | **SÍ** | `tb_ALU`: 0 errores de comprobación y 0 de bus (21/11) |
| Sistema completo sin interrupción | **SÍ** (simulación) | `tb_PICtop`: 29 comandos, 0 errores, también desde el proyecto de Vivado (23/11). Falta en placa |
| Sistema completo con interrupción | NO (no planteado) | |
| Simulación Behavioral funcionando | **SÍ** | `tb_ALU`, `tb_Terna` y `tb_PICtop` sin errores (23/11) |
| Simulación con retardos funcionando | pendiente | post-PAR prevista para otra sesión |
| Síntesis sin errores | pendiente | la última síntesis (17/11) fallaba en la ALU, ya corregida |
| Sistema funcionando en placa | pendiente | top `Nexys_PICtop` por USB‑UART |

Mejoras: rellenar con las del RS‑232 (P1) y las que se hagan después (ver `MejorasPIC.pdf`).

---

## 1) Introducción (ideas)
- Microcontrolador de aplicación específica en VHDL con arquitectura Harvard: ROM de
  programa de 12 bits y RAM de datos de 8 bits.
- Recibe comandos de 3 bytes por RS‑232 desde un PC, los decodifica y responde con 2 bytes.
- Bloques: RS232top (de la P1), DMA, RAM (dos bancos), ALU, CPU y ROM (estas dos
  proporcionadas).
- FPGA Artix‑7 `xc7a100tcsg324-1` (Nexys 4), reloj del sistema de 20 MHz (`clk_wiz` desde
  100 MHz), serie a 115 200 bps con tramas **8E1**.

---

## 2.1) Descripción del sistema

### Diagrama de bloques general (señales a dibujar)
- RS232top ↔ DMA: `RCVD_Data`, `RX_Empty`, `Data_Read`, `TX_Data`, `Valid_D`, `Ack_out`, `TX_RDY`.
- DMA ↔ CPU: `DMA_RQ`, `DMA_ACK`, `Send_comm`, `READY`.
- CPU ↔ ROM: `ROM_Addr[11..0]` y `ROM_Data[11..0]`.
- CPU ↔ ALU: `Alu_op`, `Index_Reg` y los flags `Z C N E`.
- Bus de RAM tras el arbitraje: `Address`, `Write_en`, `OE`.
- **`Databus` triestado compartido** por CPU, ALU, RAM y DMA.
- Salidas: `switches` y `Temp_H`/`Temp_L` (siete segmentos).

### Arbitraje del bus de la RAM (`PICtop.vhd`)
- `dma_owns_bus <= DMA_ACK or Send_comm`: la DMA tiene la RAM cuando la CPU le concede los
  buses (estado Receive) o le pide transmitir (estado Transmit). El resto del tiempo la
  tiene la CPU.
- Hay multiplexores en `Address`, `Write_en` y `OE`. `Databus` es un único bus triestado:
  cada bloque lo deja en `'Z'` cuando no conduce.
- Polaridades: `Reset` activo a nivel bajo y asíncrono en todo el diseño; `Write_en` activo
  a nivel alto; `OE` activo a nivel **bajo**; `Valid_D` y `Ack` activos a nivel bajo.

### RAM (Etapa 1)
- La entidad `RAM` es estructural: decodifica `Address(7..6)` y reparte `Write_en`/`OE`
  entre dos bancos.
  - `ep_ram` (0x00–0x3F): con reset asíncrono, porque son registros de significado
    específico. `T_STAT` arranca en 0x24. Salidas `Switches` (bit 0 de 0x10–0x17) y dos
    decodificadores BCD→7 segmentos para T_STAT (0x31).
  - `gp_ram` (0x40–0xFF): **sin reset**, para que Vivado la infiera como RAM distribuida
    en vez de con flip‑flops sueltos.
- La lectura es asíncrona (combinacional), y la CPU cuenta con ello: en el mismo ciclo de
  Execute pone `RAM_OE='0'` y la ALU captura el dato en el flanco.
- **Fallo de índice fuera de rango en `gp_ram` (lo destapó `tb_PICtop`, 23/11):**
  - Síntoma: XSim aborta en `T19` con `Index 0 out of bound 255 downto 64`
    (`GP_RAM.vhd`, lectura concurrente). `T19` es el primer comando que usa 0x40–0xFF
    (`WR TMP` / `LD .B, [TMP]` sobre 0x41). `tb_Terna` y el TB del profesor nunca acceden a
    esa zona, por eso no salía antes.
  - Causa: **ciclos delta**. Cada nivel de lógica combinacional añade un delta. Traza
    medida al final del `LD .B, [TMP]` (flanco de 9 827 050 ns):

    | delta | `cpu_ram_addr` | `address_mem` | `sel` | `oe_gp` |
    |---|---|---|---|---|
    | it3 | 00 | 41 | 1 | 0 |
    | it4 | 00 | **00** | 1 (viejo) | 0 (viejo) → se lee `contents_ram(0)` → error |

    Al **empezar** una lectura no pasa nada: la dirección llega antes que la habilitación
    (`address_mem` en it4, `sel` en it5, `oe_gp` en it6). Al **terminar**, la dirección cambia
    mientras la habilitación aún está activa. En hardware sería un glitch inofensivo; en
    simulación es fatal porque el índice sale del rango del tipo.
  - La escritura no tiene el problema: el `rising_edge(Clk)` se evalúa en it1, antes de
    que cambie ninguna dirección (it3 en adelante), con todos los valores estables.
  - La forma de onda no muestra deltas (un valor por instante); la traza se sacó con un
    proceso sonda que hace `report` en cada cambio (la iteración sale en el mensaje).
  - Alternativas evaluadas, sintetizando `gp_ram` aislada (xc7a100t, fuera de contexto):

    | Versión | LUTRAM | LUT lógica | Total | ¿Índice siempre en rango? |
    |---|---|---|---|---|
    | Original: array 64..255, `to_integer` directo | 24 (RAM128X1S + RAM64X1S) | 10 | 34 | no |
    | **Elegida: array 0..255** | 32 (RAM256X1S) | 9 | 41 | sí, también con `'X'` (→ 0) |
    | Array 64..255 + función que pliega a 64 | 24 | 17 | 41 | sí |
    | Array 64..255 + función que suma 64 (solo pone a 1 el bit 6) | 24 | 11 | 35 | sí |

    Vivado no recorta las 64 posiciones que nunca se escriben. Se eligió 0..255 por
    sencillez: cuesta 8 LUTRAM más (un 0,01 % de la FPGA) a cambio de que el rango quede
    garantizado por el propio tipo. Para el oral: es un intercambio de área por robustez.
    Guardar la lectura con `address` en vez de con `sel` también evitaba el error, pero no
    cubre los metavalores (`"XX" /= "00"` es verdadero y `to_integer` devuelve 0).

### DMA (Etapa 2): retos resueltos
- **La FIFO de la P1 es First‑Word‑Fall‑Through.** Al leer en un estado y escribir en el
  siguiente se guardaba el byte *siguiente* al leído (lo destapó el TB). Se arregló
  activando `Data_Read` y `Write_en` **en el mismo ciclo** (estado `RxWrite`). La DMA
  depende de que la FIFO siga en modo FWFT.
- **RX:** `RX_Empty='0'` → `DMA_RQ` → espera `DMA_ACK` → escribe en 0x00..0x02. Tras el
  tercer byte escribe 0xFF en `NEW_INST` (0x03), baja `DMA_RQ` y espera `DMA_ACK='0'`. Un
  contador `cnt` (0..3) recuerda el byte por el que va entre comandos.
- **TX:** dos estados. `TxSend` lee 0x04 y 0x05 y los entrega al transmisor; `TxDone`
  mantiene `READY='1'` hasta que baja `Send_comm`. `READY` es combinacional y baja en
  cuanto sube `Send_comm`. `Valid_D` baja solo con `TX_RDY='1'`, así que sube en el mismo
  ciclo que cae `Ack_out` (Figura 3).
- En Idle, `Send_comm` tiene prioridad sobre la recepción.
- **Interbloqueo CPU↔DMA (encontrado al integrar el 21/11, corregido el 23/11):**

  | Ciclo | CPU | DMA |
  |---|---|---|
  | n | Idle con `DMA_RQ=0` → Fetch | Idle, llega un byte → RxBusReq |
  | n+1 | Fetch del SEND (ya no mira `DMA_RQ`) | RxBusReq, `DMA_RQ=1` |
  | n+2 | Decode → Transmit, `Send_comm=1` | RxBusReq, espera `DMA_ACK` |
  | n+3… | espera `READY=1` | `READY=0`, porque no está en Idle/TxDone → **bloqueo** |

  Decisión: se arregla **en la DMA** sin tocar la CPU proporcionada. En `RxBusReq`, si
  llega `Send_comm`, pasa a TxSend. Todavía no ha leído la FIFO ni escrito en RAM, así que
  no se pierde nada, y como `RX_Empty` sigue a '0' retoma la recepción al volver a Idle.
  - **Implementación:** en `RxBusReq`, un segundo `if Send_comm = '1' then NextState <=
    TxSend` después del de `DMA_ACK`. La última asignación gana, así que `Send_comm` tiene
    prioridad. Da igual en la práctica, porque la CPU no puede estar en Receive y en
    Transmit a la vez: `DMA_ACK` y `Send_comm` son excluyentes. `READY` no hubo que
    tocarlo, porque el camino nuevo pasa por TxDone. `cnt` tampoco cambia, porque solo
    avanza en RxWrite.
  - **Evidencia:** caso 8 de `tb_Terna`. Antes del arreglo, 8b y 8c fallaban por timeout
    de READY (5 errores) y 8a pasaba gracias a la prioridad de Idle. Después pasan los tres.

### ALU (Etapa 3): cómo se ha resuelto
Estructura de la Figura 6: **registros separados del núcleo combinacional**.
- Proceso secuencial con A, B, ACC, INDEX y los flags Z, C, N, E: reset asíncrono a 0,
  carga en el flanco de subida (cada operación dura un ciclo, como exige el enunciado).
- Proceso combinacional que calcula el valor siguiente (`res_*`). **Valor por defecto =
  valor actual** de cada registro, así una operación solo cambia lo que le toca y no se
  infieren latches.
- Puertos conectados de forma concurrente desde las señales internas
  (`FlagZ <= Z`, `Index_Reg <= IDX`).
- `Databus` en `'Z'` por defecto; conduce ACC solo en `op_oeacc`.

Semántica de las operaciones (decisiones de diseño a explicar):

| Operación | ACC | Flags |
|---|---|---|
| ADD | A+B | suma en 9 bits: **C = bit 8**; **N = bit 4** de la suma de nibbles en 5 bits; Z sobre los 8 bits |
| SUB | A−B | C = bit 8 de la resta en 9 bits = **préstamo**; N = préstamo de nibble (`A(3..0) < B(3..0)`); Z |
| SHIFTL / SHIFTR | ACC desplazado, entra un 0 | ninguno |
| AND / OR / XOR | A op B | Z |
| CMPE / CMPL / CMPG | **sin cambios** | solo Z (1 = verdadero), comparación sin signo |
| ASCII2BIN | A ∈ [0x30, 0x39] → `"0000" & A(3..0)`; si no, 0xFF | E |
| BIN2ASCII | A ≤ 9 → `"0011" & A(3..0)`; si no, 0xFF | E |
| LD / mov / nop / oeacc | según el destino | **ninguno** (se conservan) |

- N es el *half‑carry* de otros micros (H en Z80/AVR, AC en 8085, DC en PIC). En la resta
  se tomó 1 = préstamo, coherente con C. En los PIC de Microchip DC va invertido, así que
  conviene justificarlo.
- Las conversiones aceptan solo 0–9 por indicación del profesor (el enunciado decía
  "menores de 0x10").
- **Por qué importa que se conserven flags y ACC (ejemplos de la ROM):**
  - `CMPE; JMPT; LD .B, I; CMPE; JMPT`: un LD entre comparación y salto no puede tocar Z.
  - `#SWITCH`: `ASCII2BIN` → `LD .A,.ACC` → `LD .B,X01` → `CMPG` → `WRI SWBASE` escribe
    **ACC**, así que la comparación no puede tocar ACC.

Errores encontrados y corregidos en la ALU (útil para "retos superados"):
1. Proceso combinacional sin valores por defecto → **latches** en `res_*`, en los flags y en
   `Databus`.
2. `FlagC`/`FlagN` sin asignar (`'U'`); flags no registrados.
3. Z calculado con el ACC **anterior** (una señal no se actualiza dentro del proceso).
4. Puertos `out` leídos dentro de la arquitectura (VHDL‑93 no lo permite) → se pasó a
   señales internas.
5. Lazos combinacionales al copiar `res_*` en `Z`/`IDX` dentro del mismo proceso.
6. Anchos: una suma de 8 bits asignada a 9; 4 bits asignados a 8 (`res_ACC <= A(3..0)`).
7. N tomando `A(4..0)`/`B(4..0)` (bit del nibble alto) en vez de ampliar `A(3..0)` a 5 bits.
8. ASCII2BIN solo miraba el nibble bajo (`'I'`=0x49 daba 9 sin error).
9. BIN2ASCII concatenaba 12 bits en 8 y no marcaba error para A ≥ 0x10.
10. `ACC = (others=>'0')` sin contexto de tipo: rompió la síntesis del 17/11.

### CPU y ROM (proporcionadas): lo revisado
- La ROM coincide con `PIC/PROGRAM` (programa hasta 0x0E0).
- La CPU es una FSM `Idle → Fetch → Decode → (Op_Fetch) → Execute → Idle`, más
  `Receive` (cede buses mientras `DMA_RQ=1`) y `Transmit` (`Send_comm=1` hasta
  `DMA_READY=1`). Registros PC, INS y TMP. Solo atiende `DMA_RQ` en Idle, entre
  instrucciones.
- Instrucciones de 1 palabra: tipo 1, `LD reg, .ACC` y SEND. El resto ocupa 2 palabras
  (pasa por Op_Fetch).
- Observaciones:
  - una instrucción de tipo 3 ilegal la dejaría bloqueada en Execute (no ocurre con esta ROM);
  - tiene el interbloqueo con la DMA descrito arriba.
  - No se modifica.

### Programa: comandos y respuestas (para explicar y para la prueba en placa)

| Comando | Acción | Respuesta |
|---|---|---|
| `I` + interruptor (0–7) + valor (0/1) | escribe en 0x10+i | `OK` / `ER` |
| `A` + actuador (0–9) + valor (0–9) | escribe en 0x20+i | `OK` / `ER` |
| `T` + decenas (0–2) + unidades (0–9) | T_STAT = BCD (displays) | `OK` / `ER` |
| `SI` + i | lee el interruptor | `S` + valor ASCII |
| `SA` + i | lee el actuador | `A` + valor ASCII |
| `ST` + cualquiera | lee T_STAT | 2 dígitos ASCII |
| otro | — | `ER` |

---

## 2.2) Simulaciones y prueba en placa

### Testbenches (los requeridos por §8.7)
- **Problema general:** `Transmit` del profesor (`RS232_test.vhd`) envía **8N1** a
  8680.6 ns por bit, pero el RS232 de la P1 usa **8E1** y descarta los bytes con paridad
  incorrecta. Los TB usan su propio `SendByte` 8E1 con un bit de 173 ciclos (8.65 µs),
  igual que P1.
- **`tb_Terna`** (`P2_ALU_CPU.srcs/sim_1/new/tb_Terna.vhd`, sucesor de `tb_DMA_RX`):
  RS232top real + DMA + RAM, con la CPU modelada en el TB. Monitor de escrituras en RAM,
  decodificador 8E1 de `RS232_TX` y comprobación de los protocolos (`Data_read` de un
  ciclo, nada sin `DMA_ACK`, bus en Z sin dueño, `Valid_D`/`Ack`).
  - Casos 1–7 (los de `tb_DMA_RX`, superado el 24/10): reset, comandos con `DMA_ACK`
    rápido y retrasado (3 bytes acumulados en la FIFO), SEND con el transmisor ocupado y
    RX durante un SEND.
  - **Modelo de CPU más fiel que en `tb_DMA_RX`:** solo concede `DMA_ACK` estando libre,
    nunca con `Send_comm='1'` (Transmit) ni con `cpu_busy='1'` (ejecutando). El modelo
    anterior concedía en cualquier momento y por eso no destapaba el interbloqueo. Es una
    lección para la memoria: un TB que modela mal el entorno da falsos aprobados.
  - **Caso 8 (interbloqueo):** llega un byte con la CPU ocupada y la CPU lanza SEND sin
    mirar `DMA_RQ`, con `Send_comm` subiendo 0, 1 y 5 ciclos después de que caiga
    `RX_Empty` (8a: la DMA aún en Idle; 8b: la carrera real; 8c: varios ciclos en
    RxBusReq). Los tres bytes forman "SI4", así que se comprueba también que el byte
    pendiente se recibe después del SEND.
  - Falló antes del arreglo (8b y 8c) y pasó después: 8 casos, 0 errores (23/11).
- **`tb_ALU`** (`P2_ALU_CPU.srcs/sim_1/new/tb_ALU.vhd`), superado el 21/11:
  - **Temporización:** los estímulos cambian en el flanco de bajada y la ALU captura en el
    de subida, así que no hay carreras.
  - **ACC:** se lee por el bus con `op_oeacc`, como lo haría la CPU. A y B se comprueban
    indirectamente, sumándolos.
  - **Monitor de bus:** comprueba en cada ciclo que la ALU no conduce fuera de `op_oeacc`
    y que no hay contención.
  - **12 casos:** reset (inicial y a mitad de ciclo); cargas y movimientos; ADD y SUB con
    casos límite de C/N/Z (0xFF+0x01, 0x0F+0x01, 0x10+0x00, 0x00+0x10, 0x0F+0x11,
    0x03−0x05…); shifts sin flags; lógicas (solo Z); comparaciones verdadera/falsa sin
    signo y sin tocar ACC; conservación de flags; conversiones con sus límites ('/', ':',
    'I', 0x0A, 0x10); y las secuencias reales de `#SWITCH` y `#TEMP`.
  - **Validación del propio TB:** contra una copia de la ALU con el fallo del bit 4 en N
    detecta 4 errores. Es un buen argumento para la memoria: el TB no aprueba cualquier
    cosa.
- **`tb_PICtop`** (`P2_ALU_CPU.srcs/sim_1/new/tb_PICtop.vhd`, VHDL‑2008), superado el 23/11:
  - Sistema completo real (RS232top, DMA, RAM, CPU, ROM, ALU) ejecutando el programa de la
    ROM. El TB hace de PC: 8E1, 115 200 bps, y espera la respuesta de 2 bytes antes de
    enviar el siguiente comando (el protocolo del programa).
  - **Caja negra:** solo mira `RS232_TX`, `switches`, `Temp_H` y `Temp_L`. Las lecturas
    se comprueban con los comandos de consulta (`SI`, `SA`, `ST`).
  - **Monitores internos con nombres externos VHDL‑2008:** 'X'/'U' en `Databus` o en el
    bus de la RAM a mitad de ciclo (contención), y un watchdog que da error si `Send_comm`
    pasa de 400 µs activo (interbloqueo CPU↔DMA).
  - 29 comandos en 7 casos: reset (displays `24`, `ST?`→`24`); `I41`/`I71`/`I40` con los
    LEDs; `I81`, `I42`, `I4X`, `IX1`→ER sin cambios; `SI7`→`S1`, `SI4`→`S0`, `SI8`→ER;
    `A35`, `SA3`→`A5`, `A90`, `SA9`→`A0`, `A3X`/`AX5`/`SAX`→ER y el actuador sigue a 5;
    `T19` (displays `19`), `ST?`→`19`, `T29`, `T31`/`T2X`→ER sin cambios, `ST0`→`29`, `T00`;
    `X12`, `SX1`, `i41`→ER; los A/T no tocan los switches; recuento total de bytes.
  - Resultado: 0 errores de estímulo, de tramas, de bus y de watchdog.
  - Primera ejecución: destapó el fallo de índice de `gp_ram` (ver RAM).
- **Por qué el TB del profesor (`PICtop_tb`) no sirve como prueba:** usa `Transmit` 8N1
  (el receptor 8E1 rechaza las tramas por paridad), solo envía `I41` y corre 1000 ns por
  defecto. No llega a la RAM de propósito general ni comprueba nada.
- **Limitación conocida del diseño (no es un fallo):** hay un solo buffer de recepción y no
  hay control de flujo. Si el PC envía un comando sin esperar la respuesta del anterior,
  los bytes nuevos pueden sobrescribir 0x00–0x02 mientras la CPU aún los está leyendo. Por
  eso el TB respeta el protocolo de esperar la respuesta (posible mejora: doble buffer).

### Placa
- Ya hecho (2a, 24/10): `Nexys_PICtop2` con lazo JA1–JA2, lectura/escritura de RAM con
  los botones, switches 0x10–0x17 en los LEDs y T_STAT en los displays.
- **Top de placa 2b** (`sources_1/new/Nexys_PICtop.vhd` + `constrs_1/new/Nexys_PICtop.xdc`,
  escritos el 24/11 a partir de los del profesor):
  - USB‑UART en vez del lazo JA: `RS232_RX <= UART_TXD_IN` (C4), `UART_RXD_OUT <= RS232_TX`
    (D4). Los nombres son los del chip USB: `TXD_IN` es lo que el PC transmite y entra a
    la FPGA. Fallo cometido por el camino: asignarlas al revés deja `RS232_TX` con dos
    drivers (el PIC y el puerto) y `RS232_RX` sin ninguno.
  - `JA`, `UART_CTS` y `UART_RTS` fuera de la entidad y comentados en el XDC. Entidad y XDC
    deben ir a la par: un puerto sin pin hace fallar el bitstream (DRC), y una restricción
    de un puerto que no existe da *critical warning*.
  - **Reset:** `reset_p <= not SW(15)` va al `clk_wiz`; `reset <= locked` va al PIC y al
    contador. `locked` ya incluye el switch, porque un MMCM en reset pone `locked='0'`.
    **Bucle evitado:** la primera versión hacía `reset <= locked and SW(15)` y
    `reset_p <= not reset`. Con `locked='0'` al arrancar, el `clk_wiz` se queda en reset
    para siempre y el PIC no arranca nunca. Regla: el reset de un generador de reloj solo
    depende de entradas externas, nunca de su propio `locked`.
  - `LED(15) <= reset`: encendido = PIC funcionando; switch arriba y LED apagado = reloj
    sin enganchar.
  - Para el oral: `locked` no está sincronizado con los 20 MHz, así que la liberación del
    reset es asíncrona (posible mejora: sincronizador de reset de 2 FF, junto con un 2.º FF
    en la línea RX, que con el USB‑UART ya es asíncrona).
- **`tb_Nexys_PICtop_timing`** (`sim_1/new`, VHDL‑2008), superado en behavioral el 24/11:
  top completo con el modelo de la IP `clk_wiz`, solo por pines (sirve tal cual para
  post‑síntesis/post‑PAR). Casos: PIC en reset con `SW(15)=0`; arranque (sale de reset
  1,05 µs después de subir el switch, en el modelo); displays `4`/`2` multiplexados;
  `I41`→`OK` + LED4, `SI4`→`S1`; reset en marcha que borra los switches y reengancha,
  `SI4`→`S0`. 0 errores y 6/6 bytes. Validación: con el bucle de reset de la primera
  versión da 8 errores.
- Pendiente: prueba con un terminal a **115200 8E1** (paridad Even) enviando los comandos
  de la tabla.

---

## 2.3) Resultados de síntesis (pendiente)
Tabla a sacar de Vivado: Slices, LUTs, FFs, DSP, BRAM, f_clk (20 MHz, WNS) y potencia.
Comprobar y comentar:
- que no se infiere ningún latch;
- que `gp_ram` sale como RAM distribuida (LUTRAM);
- que no hay DSP (la ALU es de 8 bits, solo LUTs y carry chain).

---

## 2.4) Mejoras
- Las del RS‑232 de la P1, entre ellas la paridad par (8E1).
- Pendientes de elegir (ver `MejorasPIC.pdf` y §11 del enunciado): paralelismo en la CPU,
  DMA con RX y TX simultáneas, otros formatos serie…

---

## Estado del proyecto Vivado (para no olvidarlo)
Limpieza del 23/11 (el `.xpr` solo contiene ya lo de la 2b):
- **sources_1** (top de síntesis `nexys_PICtop`): `PIC_pkg`, `ROM` y `PICtop` del repo
  (`LCSE_FPGA/PIC/`); ALU, CPU, DMA, RAM, `ep_ram` y `gp_ram` en `P2_ALU_CPU.srcs`; el
  RS232 de la P1 por referencia (`../../P1_RS232`, fuera del repo); `Nexys_PICtop.vhd`
  propio en `sources_1/new` (desde el 24/11). IPs `fifo` y `clk_wiz_0`, también de la P1.
- **constrs_1:** `Nexys_PICtop.xdc` propio en `constrs_1/new` (desde el 24/11).
- **sim_1** (top `tb_PICtop`, VHDL‑2008, `run -all`): `tb_PICtop`, `tb_Terna` y
  `tb_Nexys_PICtop_timing`. El `tb_nexys_PICtop` del profesor salió del proyecto el 24/11.
- Los originales del profesor (`Nexys_PICtop/`, `tb_Nexys_PICtop/`) se quedan intactos en
  el repo como referencia.
- Quitados del proyecto, aunque siguen en disco: los dos `RS232_test`, el TB del profesor
  (`PICtop_tb`), `tb_DMA_RX` (sustituido por `tb_Terna`), `tb_Nexys_PICtop2`, PICtop2,
  `Nexys_PICtop2` y el wcfg.
- Comprobado tras la limpieza: elaboración RTL de `nexys_PICtop` sin errores, y
  `tb_PICtop` superado con los scripts del proyecto.
- Ficheros del profesor para la placa (`Nexys_PICtop/`, `tb_Nexys_PICtop/`), a revisar
  en la próxima etapa:
  - `Nexys_PICtop.vhd` conecta el PIC al **lazo JA1–JA2** (TX→RX), no al USB‑UART. Con
    el lazo, el PIC recibe sus propias respuestas como comandos. Para hablar con el PC
    hay que usar `UART_TXD_IN` (C4) y `UART_RXD_OUT` (D4), y añadirlos al XDC.
  - `clk_wiz` con `locked => open`: el reset del PIC no espera a que enganche el reloj.
  - `tb_nexys_PICtop.vhd` **no compila tal cual**: usa `reset2` y `switches` sin
    declararlos, y `Transmit` sin `use work.RS232_test.all`. Además, ese `Transmit` es
    8N1. Para la simulación con retardos se adaptará `tb_PICtop` (con un genérico que
    desactive los nombres externos, que no existen en un netlist).

## Próxima sesión
1. ~~El usuario corrige el interbloqueo en `DMA.vhd`~~ y ~~Claude escribe `tb_Terna`~~
   (hecho el 23/11).
2. ~~Claude escribe `tb_PICtop`~~ (hecho el 23/11; destapó el fallo de `gp_ram`, ya
   corregido).
3. ~~Top de placa `Nexys_PICtop` y su XDC (los escribe el usuario)~~ (hecho el 24/11,
   con `tb_Nexys_PICtop_timing` superado).
4. Limpieza del proyecto (quitar `tb_DMA_RX`, los `tb_PICtop` antiguos, el `RS232_test`
   duplicado y lo de PICtop2), síntesis, implementación y bitstream.
5. Simulación post‑síntesis/post‑PAR con `tb_Nexys_PICtop_timing` y prueba en placa con un terminal a
   115200 8E1.
