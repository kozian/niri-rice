# Аппаратная настройка MacBook10,1

Целевая модель — MacBook10,1 (12″ Retina, 2017), без T2, с Intel HD
Graphics 615. Зафиксируйте точную ревизию, версию ядра, дату прошивок
и результат на конкретном экземпляре. На момент аудита пакет Arch
`linux` опубликован как `7.3.5.arch1-1`. Успех на 6.18 или на другом
MacBook не подтверждает исправление на текущем ядре.
[Версия linux в Arch](https://archlinux.org/packages/core/x86_64/linux/)

`install.sh` развёртывает пользовательское окружение. Прошивки, модули,
udev, quirks libinput, параметры systemd-boot, initramfs и logind
проверяются отдельно. Для первичного теста оставьте крышку открытой,
используйте USB-тетеринг как резервный канал и держите под рукой
внешнюю USB-клавиатуру или загрузочный носитель.

## Исходные данные

Запишите результат непосредственно на MacBook. Для `lspci`, `lsusb`,
`libinput`, `fbset` и ALSA-утилит используйте доступные локально
диагностические инструменты.

```sh
cat /sys/class/dmi/id/product_name
uname -r
pacman -Q linux linux-firmware-broadcom libinput systemd
lspci -nnk
lsusb
journalctl -b -k
cat /sys/power/mem_sleep
cat /sys/power/state
ls /sys/class/backlight /sys/class/leds /sys/class/power_supply
```

## Дисплей и ввод

| Область | Что известно и как проверить |
|---|---|
| EFI framebuffer и TTY | На целевой машине заявлена геометрия 2560×1600 при панели 2304×1440. Зафиксируйте, на каком этапе она видна: systemd-boot, ранний TTY или TTY после загрузки i915. Сравните `/sys/class/graphics/fb*/name`, `fbset -i`, сообщения simpledrm/i915 и `/sys/class/drm/card*-eDP-*/modes`. В niri отдельно выполните `niri msg outputs` и проверьте текущий режим 2304×1440 и scale 2.0. Изменение KDL не исправляет ранний EFI framebuffer. Подтверждённого системного исправления для этой конфигурации пока нет. [Документация EFI framebuffer](https://docs.kernel.org/fb/efifb.html) |
| SPI-клавиатура и трекпад | `applespi` входит в Linux и содержит проработку семейства MB8/9/10. Проверьте устройства через `libinput list-devices`, наличие SPI-сообщений в журнале, повторные холодные загрузки и первый ввод на TTY. Привязка к внешнему модулю не требуется, если штатный стек работает. [Драйвер applespi](https://github.com/torvalds/linux/blob/master/drivers/input/keyboard/applespi.c) · [hwdb systemd](https://github.com/systemd/systemd/blob/main/hwdb.d/60-evdev.hwdb) |
| Palm rejection | В отчёте для MacBook10,1 описано несовпадение vendor ID `06cb` с quirk для Apple `05ac`. Сначала проверьте текущие ID и правила командой `libinput quirks list /dev/input/eventN`. При печати с опорой ладони курсор не должен прыгать. DWT в KDL подавляет случайный ввод при наборе, дополнительный размерный quirk оценивайте отдельно. [macbook-arch-system](https://github.com/juicecultus/macbook-arch-system) · [Проверка quirks](https://wayland.freedesktop.org/libinput/doc/latest/device-quirks.html) |
| Жесты и чувствительность | Проверьте касания, физический клик, two-finger scroll, drag и свайпы niri. Сравните `scroll-factor 0.5` с 1.0, если прокрутка слишком медленная. Проверьте жесты с включённым natural scrolling. [Ввод и чувствительность niri](https://github.com/niri-wm/niri/wiki/Configuration:-Input) |
| Fn-клавиши и подсветка | Запишите события встроенной клавиатуры до и после модификатора Fn через `libinput debug-events` или Wayland-инспектор. Проверьте отдельно `/sys/class/backlight` для дисплея и `/sys/class/leds` для клавиатуры. Если устройство подсветки клавиатуры отсутствует, сначала определите управляющий драйвер. Имена LED и настройки Fn следует брать с машины. [Драйвер applespi](https://github.com/torvalds/linux/blob/master/drivers/input/keyboard/applespi.c) |

## Связь, аудио и камера

| Область | Что известно и как проверить |
|---|---|
| Broadcom BCM4350C2 | Проверьте PCI ID и привязку к `brcmfmac`, затем журнал загрузки firmware. В актуальном пакете Arch есть `brcmfmac4350c2-pcie.bin.zst`. Предупреждение о первом запросе board-specific файла оценивайте вместе с последующей загрузкой общего файла и появлением устройства. Проверьте соединение на 2,4 и 5 ГГц, переподключение и повторный старт после холодной загрузки. [Пакет firmware Arch](https://archlinux.org/packages/core/any/linux-firmware-broadcom/files/) |
| Динамики и микрофон | Сверьте кодек и subsystem ID в `/proc/asound/card*/codec#*`, вывод `wpctl status`, устройства ALSA и профили. Проверьте левый/правый канал на малой громкости, наушники и отдельно запись встроенного микрофона. Общественные решения для CS4208 описывают работающий вывод и отдельное исправление входа на 6.17 Ubuntu. Совместимость с текущим Arch и безопасность настройки усилителя требуют самостоятельной проверки. [Драйвер CS4208 для MacBook12](https://github.com/leifliddy/macbook12-audio-driver) · [Отчёт об исправлении микрофона MacBook10,1](https://github.com/neron82/macbook10-1-internal-mic-linux) |
| Камера | По `lspci -nnk` и `ls /dev/video*` определите фактический контроллер. Если присутствует Broadcom 1570, изучите внеядерный FaceTimeHD и условия получения firmware. После отдельной установки проверьте поток и разрешение в Firefox. Для другого PCI ID диагностику начните с подходящего штатного драйвера. [Проект FaceTimeHD](https://github.com/patjak/facetimehd) |

## Сон, питание и температура

- `macbook-sleep` описывает сбои deep/S3 и s2idle на MacBook10,1,
  опыт с COSMIC, Linux 6.18, Btrfs и дисковым swap для гибернации.
  Указанный там установщик рассчитан на другой стек. Для ext4 и zram
  нужно отдельно проектировать дисковый swap и resume-конфигурацию.
  До экспериментальной проверки тестируйте выключение экрана
  независимо от сна. Политика logind может усыпить MacBook при закрытии
  крышки даже при выключенных таймерах suspend в окружении.
  [Отчёт macbook-sleep](https://github.com/juicecultus/macbook-sleep) ·
  [Режимы сна Linux](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html)
- Зафиксируйте доступные режимы из `/sys/power/mem_sleep` и
  эффективную конфигурацию `systemd-analyze cat-config systemd/logind.conf`.
  Сначала проверьте блокировку на событиях logind без сна. Затем
  сохраните работу и проверьте отдельно один выбранный режим сна и
  закрытие крышки. После пробуждения проверьте eDP, SPI, Wi-Fi, звук,
  USB и состояние блокировки. При зависании соберите `journalctl -b -1 -k`
  после перезапуска. Переходите к серии повторов только после успешной
  одиночной проверки. [Справочник logind](https://man.archlinux.org/man/logind.conf.5.en)
- Для датчика освещённости сначала проверьте обнаружение штатным
  ядром в IIO/hwmon и изменение показаний при изменении света.
  `macbook-arch-system` использует `acpi_call` для изменения яркости
  и демон переключения power profile при изменении AC. Это отдельные
  системные эксперименты, требующие сверки с текущим ядром и оценкой
  влияния на ручное управление яркостью. [macbook-arch-system](https://github.com/juicecultus/macbook-arch-system)
- Сравните разряд в простое и при воспроизведении веб-видео при одной
  яркости и сетевой конфигурации. Запишите температуру доступных
  thermal zones, температуру корпуса, признаки троттлинга и расход
  по доступным данным power_supply. Проверьте отключение/подключение
  зарядки, статусы Charging, Full и Discharging, дайте запас на
  30-секундный интервал Waybar. Сверьте имена BAT0 и ADP1 с sysfs.
  Только после проверки базовых показателей рассматривайте udev-сигнал
  для мгновенного обновления, дополнительные профили или ACPI-автоматику.
  [Исходное поведение Waybar](https://github.com/juicecultus/hyprland-rice) ·
  [Интерфейс power_supply](https://docs.kernel.org/power/power_supply_class.html)
