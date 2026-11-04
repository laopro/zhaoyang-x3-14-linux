# zhaoyang-x3-14-linux

Arreglos de S0ix (modern standby) y batería para la **Lenovo ZhaoYang X3-14
IRL** en Linux.

> ### ⚠️ Alcance
>
> **Esto es para un solo modelo de laptop: Lenovo ZhaoYang X3-14 IRL,
> `product_name` `83GX`.**
>
> Funciona en **cualquier distribución de Linux** — Fedora, Arch, Debian,
> Ubuntu, openSUSE, la que sea — porque son solo reglas de udev, opciones de
> modprobe y un hook de systemd-sleep. Nada aquí es específico de una distro.
>
> Pero **no** es un arreglo genérico para Realtek, ni un tweak general de
> energía para Linux. Revierte a propósito una decisión de seguridad que toma
> el kernel, y esa decisión es correcta en otro hardware. `install.sh` se
> niega a correr en cualquier otra máquina, intencionalmente. Ver
> [Riesgo](#riesgo).

Para saber si este repo es para tu equipo:

```bash
cat /sys/class/dmi/id/product_name    # esperado: 83GX
cat /sys/class/dmi/id/product_family  # esperado: ZhaoYang X3-14 IRL
```

---

## El problema

De fábrica, esta laptop **nunca entra en S0ix**. Suspende y despierta bien,
todo funciona — nomás se come la batería como si estuviera despierta. Eso es
lo que lo hace fácil de pasar por alto: no hay síntoma visible, solo la
batería en el piso a la mañana siguiente.

Residencia S0ix medida antes del arreglo: **0 %**.

## La causa

En un Intel Alder Lake-U, entrar a S0ix es una cadena donde cada eslabón
tiene que aguantar:

```
todos los enlaces PCIe llegan a L1.2
        ↓
el PCH puede bajar a PC8/PC9/PC10
        ↓
se afirma SLP_S0#
        ↓
S0ix real  (~0.35 W)
```

Si **un solo** enlace PCIe se queda arriba, la cadena entera se cae y la
máquina se queda en una suspensión falsa: la CPU está detenida pero el chipset
sigue alimentado, consumiendo unos **2.5 W** en vez de 0.35 W.

El bloqueo en esta placa es la **Realtek RTL8168h** (`02:00.0`, el ethernet
por cable). El driver `r8169` **deshabilita ASPM a propósito** en esta familia
de chips — hay errata de hardware documentada donde ASPM provoca pérdida de
paquetes y cuelgues del NIC en ciertas combinaciones de placa y BIOS. Es una
decisión conservadora del driver: sacrifica energía por estabilidad.

El efecto colateral en esta laptop es que el root port del NIC nunca llega a
L1.2, así que el paquete nunca pasa de PC3, así que `SLP_S0` nunca se afirma —
y la plataforma entera pierde el modern standby por una tarjeta de red que, en
una laptop, normalmente ni tiene cable conectado.

## El arreglo

Una regla de udev vuelve a habilitar ASPM L1/L1.1/L1.2 **después** de que el
driver se engancha — el orden importa, porque `r8169` lo apaga al cargar.
También se pone runtime power management en `auto` para los dispositivos PCI,
que es lo que `powertop` marca como *Bad* por defecto.

Dos limpiezas opcionales, ninguna relacionada con S0ix: el códec HDA se apaga
tras 1 s en vez de 10 s, y se pone en blacklist `spd5118` (el sensor de
temperatura del SPD de la DDR5, que falla con `-6` en cada resume en esta
placa).

## Resultados

Medido en una Lenovo 83GX, i3-1315U, batería de 45.76 Wh, Fedora 44:

| | Antes | Después |
|---|---|---|
| Residencia S0ix | 0 % | **99.9 %** |
| Consumo dormida | ~2.5 W | **0.358 W** |
| Gasto por hora dormida | — | **0.78 %/h** |
| Consumo de paquete, idle despierta | 2.68 W | 2.04 W |

Dos suspensiones independientes, de duración deliberadamente distinta,
coincidiendo dentro del 1 %:

```
slept=2.31 h  drain=0.820 Wh  avg=0.354 W  %/h=0.77  S0ix=99.9%
slept=5.31 h  drain=1.900 Wh  avg=0.358 W  %/h=0.78  S0ix=99.9%
```

Esa coincidencia es justamente el punto. Descarta que haya wakeups
acumulándose en suspensiones largas, descarta un gasto que se degrada con el
tiempo, y descarta que sea un artefacto de la resolución gruesa del
controlador embebido. En la práctica: **≈5.3 días** de standby, **6 %** en una
noche de 8 horas, **38 %** en un fin de semana de 48 horas.

## Instalación

```bash
git clone https://github.com/laopro/zhaoyang-x3-14-linux
cd zhaoyang-x3-14-linux
sudo ./install.sh
```

Opciones: `--no-modprobe` (omite las limpiezas de audio y spd5118),
`--no-tools` (omite el hook de medición), `--force` (ignora el chequeo de
hardware — lee [Riesgo](#riesgo) primero).

Si dejas el blacklist de `spd5118`, regenera tu initramfs en caso de que ese
módulo venga incluido: `dracut --force`, `update-initramfs -u` o
`mkinitcpio -P`.

## Verificar

Cierra la tapa, déjala **al menos una hora**, y luego:

```bash
cat /var/log/s0ix-drain.log
```

La hora no es una sugerencia arbitraria. El controlador embebido solo reporta
la capacidad en porcentajes enteros, y 1 % son ~0.46 Wh en esta batería — así
que una suspensión corta gasta menos de lo que el sensor puede resolver y el
número que sale no significa nada. El hook incluido lee `energy_now`
directamente a cada lado de la suspensión, que es más fino, pero igual
necesita tiempo transcurrido suficiente.

Estado de ASPM en vivo:

```bash
cat /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm   # esperado: 1
```

## Riesgo

**Lee esto antes de usar `--force`.**

El driver `r8169` deshabilita ASPM en la familia RTL8168 por errata real de
hardware. Este repo lo vuelve a habilitar. En esta placa funciona, y las
mediciones de arriba son honestas — pero hay un hueco importante en esa
evidencia:

> **El enlace de ethernet nunca estuvo arriba durante las pruebas.**
> `NO-CARRIER`, sin cable, en todas las líneas del log. El modo de falla que
> ASPM provoca en estos chips — paquetes perdidos, TX timeouts, link flapping
> — solo se manifiesta con el enlace activo llevando tráfico. Entonces lo que
> se demostró es que ASPM no rompe una tarjeta de red que no está haciendo
> nada.

Eso está bien si usas WiFi, que es la razón por la que nunca salió a flote
aquí. Si usas el puerto por cable intensamente, considéralo no probado y
mantente alerta.

Si tu ethernet por cable empieza a perder paquetes, a cortarse o a trabarse,
este repo es lo primero que hay que sospechar, no lo último. Se prueba al
instante:

```bash
echo 0 | sudo tee /sys/bus/pci/devices/0000:02:00.0/link/l1_2_aspm
```

Si eso lo arregla, corre `sudo ./uninstall.sh` y abre un issue con tu
`product_name`, la `revision` del NIC, y qué viste.

Los candados existen por esto. `10ec:8168` es el ID PCI de GbE Realtek más
común que existe — cubre RTL8111/8168/8211/8411 en decenas de revisiones de
chip, en millones de placas de escritorio. Una regla que matcheara solo ese ID
se dispararía en todas. Por eso el match de udev únicamente selecciona *a qué*
dispositivo preguntarle; el script auxiliar decide *si* actuar, después de
revisar DMI y la revisión del chip (`0x15`, XID 541).

## Desinstalar

```bash
sudo ./uninstall.sh            # agrega --purge-log para borrar el log de mediciones
```

## ¿Misma placa, SKU distinto?

La línea ZhaoYang se revende con otras marcas según el mercado, así que la
misma placa (`LNVNB161216`) puede venir con otro `product_name`. Si tu DMI es
distinto pero el hardware es el mismo, agrega tu SKU a `SUPPORTED_MODELS` en
`install.sh` y en `lib/aspm-r8169-fix.sh`, confirma que tu NIC reporte
`revision` `0x15`, y por favor abre un PR con tus strings de DMI y tu
`s0ix-drain.log` — tener datos de más de una unidad sirve de verdad.

## ¿Por qué no un parche al kernel?

Porque el arreglo correcto upstream no es obvio, y la evidencia que hay aquí
no alcanza para uno. Re-habilitar ASPM en `r8169` es de las áreas más
revertidas del árbol de red: se habilita, se rompe para un subconjunto de
usuarios, y se vuelve a restringir. Un parche basado en una laptop con el
cable desconectado sería rechazado, con razón.

Lo que sí está mal documentado upstream es el **costo energético** de esa
decisión — mucha gente sabe que ASPM está apagado en estos NICs; poca ha
medido que le cuesta a la plataforma el modern standby completo. Eso vale
reportarlo a `netdev` como dato, no como parche. Mientras tanto, una regla de
udev es el lugar correcto para una política que el kernel no puede asumir sin
riesgo para todos.

## Archivos

| Ruta | Para qué |
|---|---|
| `udev/90-zhaoyang-power.rules` | dispara el arreglo de ASPM al bind del driver; runtime PM de PCI |
| `lib/aspm-r8169-fix.sh` | re-habilita ASPM, con candados de DMI y revisión |
| `modprobe/zhaoyang-power.conf` | power save del códec HDA; blacklist de `spd5118` |
| `tools/s0ix-drain` | hook de systemd-sleep, registra gasto y S0ix por suspensión |
| `docs/diagnosis.md` | cómo se rastreó esto, y cómo re-diagnosticarlo |

## Limitaciones conocidas

- **El panel no tiene PSR.** Por eso PC10/DC5-6 en runtime son imposibles, así
  que el S0ix en runtime con la tapa abierta se queda en 0 %. Eso es silicio,
  no configuración, y no hay tuneo que lo cambie. La suspensión no se ve
  afectada.
- **`ucsi_acpi` agrega ~1.1 s al resume** (un timeout del EC). Constante en
  todas las suspensiones. Es latencia, no energía.
- **`snd_hda_intel power_save=1` puede leerse como `10`.** Algunas distros,
  Fedora entre ellas, lo pisan en runtime desde sus propias reglas. La
  diferencia son unos pocos mW; no vale la pena pelearlo.

## Licencia

MIT. Ver [LICENSE](LICENSE).
