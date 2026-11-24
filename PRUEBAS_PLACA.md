# Pruebas en placa del PIC (Nexys A7 + PuTTY)

Guion para probar el top `nexys_PICtop` por el USB‑UART. Los comandos y respuestas son
los mismos que comprueba `tb_PICtop` en simulación, en el mismo orden, así que cada
fallo se puede comparar con la simulación.

## 1. Preparación

1. Micro‑USB al puerto **PROG/UART** y placa encendida (interruptor POWER).
2. Puerto COM: **Administrador de dispositivos → Puertos (COM y LPT) → "USB Serial Port (COMn)"**.
3. Vivado: **Open Hardware Manager → Open Target → Auto Connect → Program Device** con
   `P2_ALU_CPU/P2_ALU_CPU.runs/impl_1/nexys_PICtop.bit`.
4. **SW15 arriba** (los demás switches no se usan).

Estado esperado tras programar:
- [ ] LED15 encendido (PIC funcionando)
- [ ] punto decimal del display de la derecha parpadeando
- [ ] displays de la derecha en **`24`** (T_STAT tras el reset)
- [ ] LEDs 0–7 apagados

Si LED15 está apagado con SW15 arriba, el reloj no ha enganchado (`locked`): parar y revisar.

## 2. PuTTY (sesión guardada `Nexys_PIC`)

| Panel | Opción | Valor |
|---|---|---|
| Session | Connection type | Serial |
| Session | Serial line / Speed | `COMn` / `115200` |
| Connection → Serial | Data bits / Stop bits | `8` / `1` |
| Connection → Serial | Parity | **Even** |
| Connection → Serial | Flow control | **None** |
| Terminal | Local echo | Force on (se lee `I41OK`) |
| Terminal | Local line editing | **Force off** |

Para cambiar la configuración: cerrar la sesión, cargar `Nexys_PIC`, cambiar, **Save** y Open.

## 3. Reglas

- **Nada de Enter ni Retroceso:** envían un byte (CR = 0x0D, DEL = 0x7F).
- Escribir los 3 caracteres y **esperar las 2 letras de respuesta** antes del siguiente
  comando. Las mayúsculas cuentan.
- **Si se teclea algo incorrecto, reset (bajar y subir SW15) antes de seguir.** El PIC
  agrupa los bytes de 3 en 3 sin control de flujo: un byte de más o de menos desplaza
  todos los comandos siguientes y todo responde `ER`. El reset deja la DMA esperando el
  primer byte de un comando.
- Tras un reset, todo vuelve al estado inicial: displays `24`, LEDs apagados y
  actuadores a 0. Si hace falta, repetir la secuencia desde el principio del bloque.

## 4. Secuencia de pruebas

Marcar cada fila al comprobarla; anotar en "Obtenido" lo que salga si no coincide.

### A. Estado inicial
| ✓ | Escribir | Respuesta | En la placa | Obtenido |
|---|---|---|---|---|
| [ ] | `ST?` | `24` | displays `24` | |

### B. Interruptores remotos (LEDs 0–7)
| ✓ | Escribir | Respuesta | En la placa | Obtenido |
|---|---|---|---|---|
| [ ] | `I41` | `OK` | se enciende LED4 | |
| [ ] | `I71` | `OK` | LED4 y LED7 encendidos | |
| [ ] | `I40` | `OK` | se apaga LED4; LED7 sigue | |
| [ ] | `I81` | `ER` | sin cambios (no existe el interruptor 8) | |
| [ ] | `I42` | `ER` | sin cambios (el valor solo puede ser 0 o 1) | |
| [ ] | `I4X` | `ER` | sin cambios | |
| [ ] | `IX1` | `ER` | sin cambios | |

### C. Lectura de interruptores
| ✓ | Escribir | Respuesta | Obtenido |
|---|---|---|---|
| [ ] | `SI7` | `S1` | |
| [ ] | `SI4` | `S0` | |
| [ ] | `SI8` | `ER` | |

### D. Actuadores (no se ven en la placa: se comprueban leyéndolos)
| ✓ | Escribir | Respuesta | Obtenido |
|---|---|---|---|
| [ ] | `A35` | `OK` | |
| [ ] | `SA3` | `A5` | |
| [ ] | `A90` | `OK` | |
| [ ] | `SA9` | `A0` | |
| [ ] | `A3X` | `ER` | |
| [ ] | `AX5` | `ER` | |
| [ ] | `SAX` | `ER` | |
| [ ] | `SA3` | `A5` (los errores no lo han cambiado) | |

### E. Termostato (displays)
| ✓ | Escribir | Respuesta | En la placa | Obtenido |
|---|---|---|---|---|
| [ ] | `T19` | `OK` | displays `19` | |
| [ ] | `ST?` | `19` | | |
| [ ] | `T29` | `OK` | displays `29` | |
| [ ] | `T31` | `ER` | siguen en `29` (las decenas van de 0 a 2) | |
| [ ] | `T2X` | `ER` | siguen en `29` | |
| [ ] | `ST0` | `29` | (el tercer carácter da igual) | |
| [ ] | `T00` | `OK` | displays `00` | |

### F. Comandos inválidos
| ✓ | Escribir | Respuesta | Obtenido |
|---|---|---|---|
| [ ] | `X12` | `ER` | |
| [ ] | `SX1` | `ER` | |
| [ ] | `i41` | `ER` (minúscula) | |

### G. Final
| ✓ | Comprobación | Esperado | Obtenido |
|---|---|---|---|
| [ ] | LEDs | solo LED7 encendido (los comandos A y T no tocan los switches) | |
| [ ] | `SI7` | `S1` | |

### H. Reset en marcha
| ✓ | Acción | Esperado | Obtenido |
|---|---|---|---|
| [ ] | Bajar SW15 | LED15 y LED7 se apagan | |
| [ ] | Subir SW15 | LED15 se enciende; displays `24` | |
| [ ] | `SI7` | `S0` | |
| [ ] | `SA3` | `A0` | |

## 5. Si algo falla

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Todo responde `ER` | Bytes desplazados (un carácter de más o de menos) | Reset con SW15 y repetir el comando |
| Todo `ER` incluso tras el reset; `I41` sí enciende LED4 | PuTTY sin paridad (8N1): solo pasan los caracteres con nº impar de unos (`I T X 1 2 4 7 8`) | Parity = Even, Save, reabrir |
| No responde nada | Paridad Odd, COM equivocado o LED15 apagado | Revisar PuTTY y el reset |
| Caracteres raros | Velocidad distinta de 115200 | Revisar Speed |
| PuTTY no envía hasta pulsar Enter | Local line editing activado | Force off |

## 6. Evidencia para la memoria

- [ ] Captura de PuTTY con toda la secuencia (con el eco: `ST?24I41OKI71OK…`)
- [ ] Foto tras `I71` (bloque B): LED4 y LED7 encendidos, displays `24`
- [ ] Foto tras `T19` (bloque E): displays `19`, solo LED7
- [ ] Foto tras `T00` (final de E): displays `00`, solo LED7
- [ ] Anotar fecha y resultado en `NOTAS_MEMORIA.md` y cerrar la fila
      "Sistema funcionando en placa"
