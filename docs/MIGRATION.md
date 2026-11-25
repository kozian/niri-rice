# Миграция с hyprland-rice

Исходная ревизия в локальном клоне — `f2d7824`, конфигурация
Justinian (juicecultus). Проверены README, установщик и указанный
в нём перечень пакетов, профиль Bash, все активные конфиги и файлы
обеих тем, скрипты панели и меню, размеры и совпадения обоев, а также
история лицензий. В локальной истории и в корне upstream не найдено
LICENSE или условий повторного распространения. Унаследованные обои
и CSS сохранены для работы в предоставленном клоне. Для публикации
требуется разрешение на повторное использование материалов или их
замена. [Исходник](https://github.com/juicecultus/hyprland-rice)

## Что перенесено

| Исходная функция | Реализация |
|---|---|
| EDID eDP-1, HiDPI, тачпад, клавиатура, клавиши и декорации в `hyprland.conf` | niri KDL. 2× из раздела дисплея ТЗ и исходного конфига. Три пальца работают по стандартной схеме niri. Клавиши сохраняют привычные запуск и действия, движение по колонкам следует scrolling tiling |
| Dwindle, split и pseudo, фокус/перемещение, рабочие пространства | Колонки niri, ширины, поглощение и вынос окон, пять именованных пространств и динамические дополнительные. Super+L оставлен для блокировки, поэтому у фокуса вправо есть стрелка |
| Правила для pavucontrol, редактора NetworkManager, btop, CAVA, Satty и полупрозрачность Thunar | Специальные правила этих приложений убраны. Скругление и градиент фокуса перенесены. Диалоги используют подсказки приложений |
| Waybar с «капсулами», часами, треем и значками | Оригинальная компоновка и цвета, нативные `niri/workspaces`, `niri/window`, `wireplumber`, `backlight`. Батарея сохраняет BAT0/ADP1 и поддержку сигнала 8 |
| `network.sh` и `battery-status` | NetworkManager для BCM4350 и ethernet-тетеринга. Новый сетевой скрипт экранирует поля JSON через jq и читает кэш без активного сканирования. Батарея продолжает обновляться раз в 30 с, внешний udev-сигнал может ускорить обновление |
| Alacritty и `term-exec` | Foot с ANSI-палитрами, CaskaydiaCove Mono 11 pt, отступами, блочным курсором и прозрачностью. Fuzzel умеет сам запускать `Terminal=true` через Foot |
| Wofi drun, dmenu и отдельные CSS для подсказки и питания | Fuzzel с адаптированной палитрой и округлой рамкой, dmenu для питания и буфера, встроенная подсказка niri |
| SwayNC и два CSS | Сохранены палитры, уведомления, центр, DND, MPRIS и кнопки. Команды блокировки, скриншота, темы и питания используют новые интерфейсы. Панель подписывается через `swaync-client -swb` |
| Hyprlock/Hypridle, DPMS и `loginctl lock-session` | Swaylock через единственный systemd unit с ожиданием готовности, Swayidle с таймерами и обработчиками logind. Статический фон в цветах темы без размытого снимка рабочего стола |
| `wpaperd` и наборы обоев | Исходные четыре изображения и 15-минутная ротация, режим fit сохраняет пропорции на внешних дисплеях. Повторявшиеся превью `wallpaper.png` заменены ссылкой README на исходный файл набора |
| `theme-toggle`, `hyprctl reload`, копирование CSS | Единая атомарная ссылка темы. niri перезагружает KDL через IPC, Waybar перечитывает CSS по SIGUSR2, SwayNC по своему IPC, wpaperd перезапускается своим unit |
| Grim/Slurp, Satty, Hyprpicker | niri делает снимок области, экрана или окна. Редактор аннотаций исключён из минимального состава |
| `volume-ctl`, pamixer и click feedback | Громкость и mute через wpctl. Дополнительные libcanberra и sound-theme-freedesktop ради щелчка исключены, текущий уровень показан в Waybar |
| `start-hyprland`, перезапись профиля и рекомендованный autologin | Хук в существующем Bash login-профиле. Пуск только на интерактивной локальной TTY1, с проверкой активного сеанса и защитой от рекурсивного запуска |
| `install.sh`, копирование в HOME и печать списка | Установка пакетов полной транзакцией и пофайловое развёртывание с dry-run, проверкой KDL, резервными копиями и инвентарём |

## Зависимости и протоколы

- niri, SwayNC, Waybar, Fuzzel и wpaperd используют Wayland. Панель,
  лаунчер, уведомления и обои используют layer-shell. Swaylock использует
  ext-session-lock, Swayidle — ext-idle-notify, wl-clipboard — data
  control для фонового наблюдения. `xdg-mime` из `xdg-utils` помогает
  `wl-copy` определить MIME при восстановлении изображений. Waybar читает рабочие пространства
  и окно через niri IPC. [Поддержка протоколов niri](https://wayland.app/compositors/niri) ·
  [Модуль Waybar](https://man.archlinux.org/man/waybar-niri-workspaces.5.en) ·
  [Swayidle](https://man.archlinux.org/man/swayidle.1.en)
- Пользовательский systemd запускает компоненты после готовности
  `niri.service`. Drop-in привязывает штатный `swaync.service` к тому же
  сеансу, включая случай D-Bus-активации. Фоновые процессы останавливаются
  вместе с niri. Наблюдатели clipboard разделены по MIME-классу.
  [niri.service](https://github.com/niri-wm/niri/blob/v26.04/resources/niri.service) ·
  [Файлы пакета SwayNC](https://archlinux.org/packages/extra/x86_64/swaync/files/)
- polkit-gnome предоставляет самостоятельный GTK-агент. Библиотека
  Polkit при поиске сеанса учётной записи поддерживает fallback через
  logind display session для процессов пользовательского systemd.
  Графический диалог и регистрацию агента следует проверить в живом
  сеансе MacBook. [Пакет агента](https://archlinux.org/packages/extra/x86_64/polkit-gnome/files/) ·
  [Реализация Polkit](https://github.com/polkit-org/polkit/blob/master/src/polkit/polkitunixsession-systemd.c)
- Arch Waybar требует реализацию JACK. По умолчанию явно выбран
  `pipewire-jack`, а при установленном `jack2` сохраняется текущий
  провайдер. Для Firefox явно задан `noto-fonts` как `ttf-font`.
  GTK portal выбран для виртуальной зависимости niri. GNOME portal
  обслуживает только опциональный ScreenCast, включая PipeWire и
  файловую зависимость Nautilus в Arch. [Waybar](https://archlinux.org/packages/extra/x86_64/waybar/) ·
  [Firefox](https://archlinux.org/packages/extra/x86_64/firefox/) ·
  [Порталы niri](https://github.com/niri-wm/niri/wiki/Important-Software)
- Исключены Hyprland, Hypridle, Hyprlock, Hyprpicker, портал Hyprland,
  hyprpolkitagent, Wofi, Alacritty, CAVA, Satty, Grim, Slurp, pamixer,
  qt6ct, дополнительные звуки и их плеер. Убран глобальный набор
  переменных Qt, Electron, Java и GTK из исходника. Сервер XWayland
  по умолчанию отключён. Установщик оставляет уже установленные
  приложения и старые неуправляемые файлы в HOME. [Пакет niri](https://archlinux.org/packages/extra/x86_64/niri/)
- Одна Nerd Font семья покрывает значки панели и терминал, Noto даёт
  обычный GTK текст и emoji, Adwaita — набор значков приложений,
  Capitaine — исходный курсор. GTK использует тёмную настройку
  стандартной темы. Тема приложений Libadwaita может определяться
  их собственным менеджером стилей. Дополнительные темы GTK, Qt и
  отдельные иконочные шрифты не требуются.

## Отдельный аппаратный этап

Правила libinput palm rejection, udev-сигнал батареи,
автоматическое управление профилем питания, датчик света через
ACPI, выбор режима сна, системные драйверы и firmware относятся
к [аппаратной настройке](HARDWARE.md). Они проверяются отдельно,
после приёмки рабочего стола.


## Проверка конфигурации

В одноразовой x86_64 Linux-ВМ версии niri 26.04, Foot и Fuzzel
успешно проверили обе палитры своими командами валидации. На машине
разработки дополнительно проверены синтаксис Bash, ссылки, JSON/TOML,
уникальность сочетаний и несколько ветвей вспомогательных скриптов
с подстановкой команд. Транзакция pacman, действующие пользовательские
службы и графика на Arch проверяются на целевой системе по
[чеклисту](../CHECKLIST.md).
