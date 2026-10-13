# Visual Quote — карта кода (M1)

Результат этапа M1: как устроены нужные части Telegram-iOS и куда встраивать Visual Quote. Код не менялся. Пути указаны относительно корня репозитория, `file:line` — на коммит `f1dd7a2dbd` (master от 2026-10-12). Факты проверены чтением кода; эксперименты отмечены словом «проверено».

## 0. Главная находка: «ответ на часть сообщения» уже есть

У ответа в Telegram-iOS есть понятие **внутренней темы** — `EngineMessageReplyInnerSubject` (`submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift:12`): сейчас это `.todoItem(Int32)` (пункт списка дел) и `.pollOption(Data)` (вариант опроса). Этот механизм проходит весь путь, который нужен Visual Quote:

| Шаг | Где | Что делает для innerSubject |
| --- | --- | --- |
| Состояние композера | `ReplyMessageAttribute.innerSubject` (`submodules/TelegramCore/Sources/SyncCore/SyncCore_ReplyMessageAttribute.swift`) | хранится рядом с `quote` |
| Панель ответа над полем ввода | `ReplyAccessoryPanelNode.swift:275-318` | показывает текст пункта/варианта вместо текста сообщения |
| Отправка | `PendingMessageManager.swift:1240-1243` → `Api.InputReplyTo.inputReplyToMessage(... todoItemId, pollOption)` (`submodules/TelegramApi/Sources/Api13.swift:352`) | уходит на сервер в полях `todo_item_id:int` / `poll_option:bytes` |
| Приём | `Api.MessageReplyHeader` с теми же полями (`Api18.swift:541`) → `ReplyMessageAttribute.innerSubject` | |
| Заголовок в пузыре | `ChatMessageReplyInfoNode.swift:450-460, 531` | ищет вариант/пункт в медиа исходного сообщения и рисует его текст и медиа |
| Переход по нажатию | `ChatMessageBubbleItemNode.swift:5990` → `navigateToMessage(... subject: attribute.innerSubject)`; `getInnerReplySubjectRect(innerSubject:)` `:7655` | подсвечивает именно пункт/вариант внутри сообщения |
| Из галереи | `ChatImageGalleryItem.swift:787-804` | «Reply» в меню «ещё» уже передаёт `innerSubject` через `ChatControllerSubject.MessageHighlight(quote:subject:)` (`submodules/AccountContext/Sources/ChatController.swift:908`) |

Вывод: Visual Quote — это новый случай `innerSubject`, условно `.imageRegion(...)`. Локально (композер, панель, пузырь, переход, галерея) всё ложится на готовые точки. Единственный пробел — **сетевой формат**: в `inputReplyToMessage` нет поля для области изображения, в продакшене им стало бы поле рядом с `todo_item_id` / `poll_option` (см. раздел 5).

## 1. Просмотр фото (галерея)

**Цепочка открытия.** Тап по фото в пузыре: `ChatMessageInteractiveMediaNode.swift:668, 743, 779-792` → `ChatMessageMediaBubbleContentNode.swift:47-71` (`openMessage`) → `ChatController.swift:872, 1484-1749` (`OpenChatMessageParams`, `transitionNode`, `GalleryControllerActionInteraction`) → `OpenChatMessage.swift:32, 134, 371-409` → `GalleryController` (`submodules/GalleryUI/Sources/GalleryController.swift:707`, init `:783`) → `GalleryControllerNode.swift:12` → `GalleryPagerNode.swift:82` → `ChatImageGalleryItem.swift:120`, нода `ChatImageGalleryItemNode: ZoomableContentGalleryItemNode` `:220`.

**Где картинка.** `ZoomableContentGalleryItemNode.scrollNode: ASScrollNode` (`ZoomableContentGalleryItemNode.swift:7`), контент `zoomableContent: (CGSize, ASDisplayNode)?` `:14`; для фото это `imageNode: TransformImageNode` (`ChatImageGalleryItem.swift:232`, назначение `:523`), декодированный `UIImage` в `TransformImageNode.image` (`submodules/Display/Source/TransformImageNode.swift:26`). Для локальных файлов возможен `tilingNode` (`:242, :569-573`).

**Жесты, которые уже заняты** (`ZoomableContentGalleryItemNode.swift:44-106`):
- один `TapLongTapOrDoubleTapGestureRecognizer` на `scrollNode.view`: тап у краёв 44pt — одиночный, иначе ждёт двойной; одиночный тап прячет/показывает хром, двойной — зум `scrollNode.view.zoom(to:)` / `setZoomScale` (`:100-102`);
- **долгое нажатие по фото распознаётся, но ничем не занято**: распознаватель шлёт `.longTap` через 0.3 с (`submodules/Display/Source/TapLongTapOrDoubleTapGestureRecognizer.swift:228`, свойство `longTap` `:95`), а `contentTap` его игнорирует (`default: break`, `:104-105`);
- pinch и pan при зуме — встроенные в `UIScrollView` (`:200-248, :273-281`); листание между фото — пейджинг `GalleryPagerNode` (`:149-173`); тап у края для перелистывания — второй распознаватель на пейджере (`:193-363`); свайп вниз для закрытия — через вертикальный `scrollView` галереи (`GalleryControllerNode.swift:369, :561-630`);
- в режиме Live Text: `RecognizedContentContainer` (`ChatImageGalleryItem.swift:1586`) и `RecognizedTextSelectionNode` с собственным долгим нажатием 0.3 с (`RecognizedTextSelectionNode.swift:293, :371`) — активны только после включения распознавания текста.

**Координаты.** Контент-нода стоит в `(0,0,contentSize)` с единичным трансформом, зум — трансформ скролла (`:150-188`). Точка касания → `scrollNode.view.convert(location, to: contentView)` (`:88`), деление на `contentNode.bounds.size` даёт нормализованную точку 0…1. Готовый прецедент нормализованных прямоугольников — распознанный текст: `recognition.rect.convertTo(size:)` (`ChatImageGalleryItem.swift:1593, :1614`; `ImageContentAnalysis.swift:132`), контейнер оверлея размером с `imageNode.bounds` (`:376, :445`).

**Низ галереи.** `ChatItemGalleryFooterContentNode` (`submodules/GalleryUI/Sources/ChatItemGalleryFooterContentNode.swift`): кнопки собираются в `updateLayout` `:1178` как `GlassControlGroupComponent.Item(id:, content: .icon(...), action:)` в группы left/center/right `:1334-1443` (share / pip, settings, edit, textRecognition, stickers, fullscreen / delete), рендер `GlassControlPanelComponent` с темой `defaultDarkColorPresentationTheme` `:1450-1476`. Тема галереи всегда тёмная: `GalleryController.swift:1185`.

**Reply уже есть, но в меню «ещё»** (`ChatImageGalleryItem.swift:787-804`, строка `Conversation_ContextMenuReply`): `beginCustomDismiss(.simpleAnimation)` → `navigateToChatController(... subject: .message(id:, highlight: MessageHighlight(quote: nil, subject: innerSubject), timecode: nil, setupReply: true))` → через 0.3 с `completeCustomDismiss(false)`. Это и есть образец для кнопки «Reply» после выделения.

**Закрытие и обратная связь с чатом.** `GalleryController.dismiss(forceAway:)` `:1486`, `GalleryItemNode.beginCustomDismiss/completeCustomDismiss` (`GalleryItemNode.swift:32-34`), `actionInteraction.updateCanReadHistory` на каждом закрытии, отдельного колбэка «галерея закрыта» нет. Из элементов галереи до чата дотягиваются через `baseNavigationController()` / `galleryController()` (`GalleryItemNode.swift:35-36`) и `GalleryControllerActionInteraction` (`submodules/AccountContext/Sources/GalleryController.swift:26-66`, реализация `ChatController.swift:1607-1726`).

**Открытие с приближением к области.** Отдельного API нет; единственные вызовы зума — в обработчике двойного тапа (`scrollNode.view.zoom(to:animated:)`). `scrollNode` публичный, `activateAsInitial()` (`GalleryItemNode.swift:88`) — пустой хук, который контроллер вызывает для начального элемента. Важно: `resetScrollViewContents` сбрасывает зум при установке контента и смене размера (`:14-26, :115-133`), значит приближение нужно делать после того, как контент и layout установлены.


## 2. Полный путь текстовой цитаты (образец для копирования)

| Стадия | Где | Детали |
| --- | --- | --- |
| Выделение | `submodules/TextSelectionNode/Sources/TextSelectionNode.swift:215, 284, 735-785` | действие `.quote(range:)` в меню выделения; строка `Conversation_ContextMenuQuote`. Нода выделения создаётся, когда сообщение «поднято» в контекстное меню: `ChatMessageTextBubbleContentNode.swift:1598-1628`, условия `enableQuote` `:1653-1674` (есть текст, можно писать, не секретный чат) |
| Обработка | `ChatController.swift:4427`, ветка `.quote` `:4565-4609` | берёт подстроку, режет по `quote_length_max` (1024, `SyncCore_TextEntitiesMessageAttribute.swift:443`), собирает `EngineMessageReplyQuote(text:offset:entities:media:)` и кладёт в `ChatInterfaceState.ReplyMessageSubject(messageId:quote:innerSubject:)`, затем `withUpdatedReplyMessageSubject` и фокус в поле ввода |
| Состояние композера | `submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift:480-497, 515, 856` | `ReplyMessageSubject` зеркалит `EngineMessageReplySubject` (`EnqueueMessage.swift:117-127`); сохраняется в черновик, в том числе облачный (`:555, :679, :741`) |
| Панель над полем ввода | `submodules/TelegramUI/Components/Chat/ChatInputMessageAccessoryPanel/Sources/ChatInputMessageAccessoryPanel.swift` | активный компонент: `Contents.Reply { id, quote, innerSubject, message }` `:108-126`; высота 52 `:427`; полоска 2pt цветом `inputPanel.panelControlAccentColor` `:416-433`; стеклянная кнопка закрытия 44×44 `:435-443`; заголовок `Chat_ReplyPanel_ReplyToQuoteBy` `Font.medium(14)` `:595-637`; текст цитаты в одну строку `Font.regular(14)` `:664-667`; **код миниатюры 35×35 закомментирован** `:489-510`. Подключение: `ChatInterfaceStateAccessoryPanels.swift:23, 207-239` (тап → `presentReplyOptions`, долгое нажатие → переход к сообщению, крестик → `setupReplyMessage(nil)`). Старый `ReplyAccessoryPanelNode` отключён (`:269-271`), но содержит образцы иконки цитаты и миниатюры |
| Редактирование цитаты | `submodules/TelegramUI/Sources/Chat/ChatMessageActionOptions.swift:86, 359-579, 581-629` | превью-меню с встроенным `ChatControllerImpl` в режиме `.standard(.previewing)`; пункты «Quote Selected Part / Select Specific Quote / Remove Quote» |
| Отправка | `ChatControllerNode.swift:5024, 5171-5212` (проверка, что цитата всё ещё есть в тексте, иначе алерт `Chat_ErrorQuoteOutdated*`), `EnqueueMessage.swift:130, 1015-1037` (`ReplyMessageAttribute(... isQuote: quote != nil, innerSubject)`), `PendingMessageManager.swift:1465-1501, 1880-1912` | флаги `inputReplyToMessage`: 1<<2 `quoteText`, 1<<3 `quoteEntities`, 1<<4 `quoteOffset`, 1<<6 `todoItemId`, 1<<7 `pollOption`. Серверных ошибок `QUOTE_*` клиент не обрабатывает |
| Приём | `StoreMessage_Telegram.swift:542-563, 1138-1200` | `isQuote` = флаг 1<<9; цитата собирается, если есть `quoteText` или `replyMedia`; плюс `QuotedReplyMessageAttribute` при `replyFrom` |
| Заголовок в пузыре | `ChatMessageBubbleItemNode.swift:2149-2171, 3030-3046` → `ChatMessageReplyInfoNode.swift` | иконка цитаты `Chat/Message/ReplyQuoteIcon` справа сверху `:27-29, 928-946`; шрифт `floor(baseDisplaySize * 14/17)`, заголовок `Font.semibold`, текст `Font.regular` `:195-197`; цвета автора `:229-268`; фон и полоска `MessageInlineBlockBackgroundView` `:897-926`; **миниатюра фото в ответе: `imageSide = titleLineHeight * 2.0`** `:684-686`, скругление 4, начало (9, 4) `:797`, отступ текста `floor(baseDisplaySize * 32/17)` `:629-632`; цитата: заголовок до 2 строк, текст до 5 (50 при раскрытии) `:646-664` |
| Переход по нажатию | `ChatMessageBubbleItemNode.swift:5960-5991` → `navigateToMessage(... NavigateToMessageParams(quote:subject:))` → `ChatControllerNavigateToMessage.swift:367-376` → `ChatHistoryListNode.scrollToMessage` `:3878` | центрирование по `getQuoteRect` (`PreparedChatHistoryViewTransition.swift:223-229`, `ChatMessageBubbleItemNode.swift:7634`); после прокрутки `ChatInterfaceHighlightedState(quote:subject:)` (`ChatControllerLoadDisplayNode.swift:5454-5476`), тост `Chat_ToastQuoteNotFound`, снятие подсветки через 1.5 с; рисование: `updateHighlightedState` `:6960-7070` — подсветка всего пузыря `authorNameColor.withMultipliedAlpha(0.2)`, через 0.3 с сжимается к прямоугольнику цитаты пружиной 0.4 с |
| Строки | `Telegram/Telegram-iOS/en.lproj/Localizable.strings:10166-10257` | `Conversation.ContextMenuQuote`, `Chat.ReplyPanel.ReplyToQuoteBy`, `Chat.ToastQuoteNotFound`, `Conversation.MessageOptionsQuote*` и др. |

Ответ на фото без цитаты уже показывает в заголовке миниатюру `imageSide` (≈2 высоты строки) — именно её Visual Quote должен сделать «заметно крупнее» (раздел 2.8 задания, варианты на M4).

## 3. Тема, строки, флаги

**Тема.** `PresentationTheme` (`submodules/TelegramPresentationData/Sources/PresentationTheme.swift:1576`), получать из `context.sharedContext.currentPresentationData.with { $0 }` или сигнала `presentationData` (`submodules/AccountContext/Sources/AccountContext.swift:1415-1416`). Для пузырей: `theme.chat.message.incoming/outgoing` (`PresentationThemePartedColors` `:959`: `accentTextColor` `:967`, `accentControlColor` `:968`, `linkTextColor`, `bubble`); панель ответа красится `theme.chat.inputPanel.panelControlAccentColor` (`ReplyAccessoryPanelNode.swift:76, 262-286, 414`). Цвет отправителя для полоски и имени: `context.peerNameColors.get(nameColor, dark:)` — канонический код в `ChatMessageReplyInfoNode.swift:229-265` (входящие: пресет или `incoming.accentTextColor`; исходящие: всегда `outgoing.accentTextColor`). Галерея: `defaultDarkColorPresentationTheme` (`DefaultDarkPresentationTheme.swift:7`). Стеклянный стиль: `GlassBackgroundView.useCustomGlassImpl` (`GlassBackgroundComponent.swift:501`), флаги `fakeGlass`/`forceClearGlass`.

**Строки.** Источник — `Telegram/Telegram-iOS/en.lproj/Localizable.strings`; генератор `build-system/GenerateStrings/GenerateStrings.py` через genrule `GeneratedPresentationStrings` (`Telegram/BUILD:149-164`). Ключ `A.B.C` становится `strings.A_B_C`; значения с `%@` — функциями; суффиксы `_0/_1/_any` — плюрализацией. Достаточно добавить строку в английский файл, регистрации нет. Другие языки — пустые заглушки (`Telegram/BUILD:192-198`), при отсутствии перевода берётся английский из бандла (`GenerateStrings.py:448-480`). Это закрывает риск 5 задания: новые строки покажутся по-английски, чего для демо и достаточно.

**Флаг в Debug Settings.** `ExperimentalUISettings` (`submodules/TelegramUIPreferences/Sources/ExperimentalUISettings.swift`): поле, значение в `defaultSettings` (`:84`), параметр init, decode (`:249`, образец `decodeIfPresent(Bool.self, forKey:) ?? false` `:299`), encode (`:356`). Переключатель: `DebugController.swift` — enum case (образец `.keepChatNavigationStack`), `ItemListSwitchItem(... systemStyle: .glass ...)` и запись через `updateExperimentalUISettingsInteractively` (`:1054-1060`), добавление в список `:1872` (внутри `if isMainApp`). Чтение: `context.sharedContext.immediateExperimentalUISettings.<flag>` (`AccountContext.swift:1421`; пример `ChatTextInputPanelNode.swift:816`). Как открыть Debug Settings в залогиненном приложении: 10 быстрых тапов по иконке вкладки Settings (`TabBarController.swift:165-178` → `TelegramRootController.swift:229-234`); на экране ввода номера — 10 тапов по заголовку.

**Доступность и хаптика.** `accessibilityLabel` задаётся строками напрямую (`ReplyAccessoryPanelNode.swift:60, 326-332`). `HapticFeedback` (`submodules/Display/Source/HapticFeedback.swift:128`): `tap()`, `impact(.light/.medium/...)`, `success()`; в чате либо `HapticFeedback().impact()`, либо хранимый экземпляр.

## 4. Vision: где подключать и работает ли в симуляторе

**В кодовой базе** Vision подключается просто `import Vision`, в BUILD нигде не объявлен (только `weak_sdk_frameworks` в `submodules/LegacyComponents/BUILD:52-53`). Главный прецедент — вырезание объекта для стикеров:

- `submodules/TelegramUI/Components/MediaEditor/ImageObjectSeparation/Sources/ImageObjectSeparation.swift`: `cutoutImage(from:editedImage:crop:target:)` `:229` с `CutoutTarget.point(CGPoint?) / .index / .all` `:204-207` — точка касания сопоставляется с экземпляром по пиксельной метке `instanceMask` `:364-381`; результат `CutoutResult` с `extractedImage`, `edgesMaskImage`, `maskImage` (маска сглажена `refineEdges` `:211`: blur → contrast → sharpen). На iOS 17+ использует `VNGenerateForegroundInstanceMaskRequest`; **в симуляторе принудительно (`forceCoreMLVariant`, `:23-29`) переключается на CoreML-модель `u2netp`**, которую докачивает из канала `@stickersbackgroundseparation` (`:36-60`) — то есть нужны залогиненный аккаунт и сеть; доступность — `cutoutAvailability(context:)` `:35`.
- Вызовы: `MediaEditor.swift:931-959`, `MediaCutoutScreen.swift:122, 431`, `DrawingScreen.swift:3193` («Cut Out»), `MediaPickerScreen.swift:2410` (префетч).
- **Готовая светящаяся обводка** — `StickerCutoutOutlineView` (`submodules/TelegramUI/Components/MediaEditorScreen/Sources/StickerCutoutOutlineView.swift:9`): маска → контур (`CIMorphologyMaximum` r=3, растр 256px, обход границы, упрощение Дугласа–Пекера) → `UIBezierPath`; слои: `CAShapeLayer` с белой тенью (opacity 0.35, radius 4 `:22`), два `CAEmitterLayer` (частицы по контуру и свечение), `animateBump` 1→1.07→1 за 0.4 с `:127`. Это ближайший «язык Telegram» для подсветки выделения; для Visual Quote нужна его спокойная версия без частиц.
- Прочее: `VNClassifyImageRequest` (`ImageObjectClassification.swift:25-27`), `VNDetectFaceRectanglesRequest` + `VNGeneratePersonSegmentationRequest` (`MediaEditor.swift:2357-2385`), `VNRecognizeTextRequest`/`VNDetectBarcodesRequest` в `submodules/ImageContentAnalysis` (Live Text в галерее, `ChatImageGalleryItem.swift:371`).

Уточнение вывода по риску 2 с учётом этого: контур объекта в симуляторе **возможен через существующий CoreML-фолбэк** (`u2netp` выделяет один главный объект, а не экземпляры, поэтому в симуляторе точность ниже, чем на устройстве), при условии, что в симуляторе есть залогиненный аккаунт для загрузки модели. Это снимает необходимость сборки на устройство для M2, но для честной оценки качества контура всё равно нужен iPhone.

**Проверено в симуляторе iPhone 17 Pro, iOS 26.5** (проба — консольная программа на Vision, запущенная внутри симулятора через `xcrun simctl spawn`, на штатных фото из медиатеки симулятора):

| Запрос | Результат в симуляторе |
| --- | --- |
| `VNGenerateForegroundInstanceMaskRequest` (выделение объекта, iOS 17+) | **не работает**: `Could not create inference context`, и с `usesCPUOnly = true` тоже |
| `VNGenerateObjectnessBasedSaliencyImageRequest` | по умолчанию падает (`Failed to create espresso context`); с `usesCPUOnly = true` выполняется (~115 мс), но на тестовых фото объектов не вернул |
| `VNGenerateAttentionBasedSaliencyImageRequest` (`usesCPUOnly`) | работает, ~220 мс |
| `VNDetectContoursRequest` | работает, ~225 мс |
| `VNDetectRectanglesRequest`, `VNDetectHorizonRequest` | работают |
| `VNRecognizeTextRequest(.fast)` | работает, 100–220 мс |
| `VNDetectFaceRectanglesRequest`, `VNClassifyImageRequest`, feature print | не работают (нет inference context) |

Вывод по риску 2 задания: **главный эффект (контур объекта) в симуляторе недоступен**, нейросетевые запросы Vision требуют устройства. В симуляторе честно работает только запасной путь — кольцо в точке касания, и возможны «геометрические» подсказки (контуры, прямоугольники, текст на скриншотах). Для демо контура нужен запуск на iPhone с подписью через Apple ID Ники. Это меняет план M2 и обсуждается отдельно.

Исходник пробы: `docs/visual-quote/tools/VisionProbe.swift` (запуск: собрать `xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator`, затем `xcrun simctl spawn <udid> ./VisionProbe <image> 0.5 0.5`).

## 5. Передача координат без изменения схемы

Факты, от которых отталкиваемся:
- В `inputReplyToMessage` нет поля для области изображения, но есть два поля «внутренней темы» ответа: `todo_item_id:int` и `poll_option:bytes` (`Api13.swift:352`), и они же возвращаются в `messageReplyHeader` (`Api18.swift:541`). Клиент кладёт их из `ReplyMessageAttribute.innerSubject` (`PendingMessageManager.swift:1240-1243`) и читает обратно в `innerSubject`.
- Цитата (`quote_text`) на фото без подписи невозможна: клиент создаёт цитату только при непустом тексте (`ChatController.swift:4580-4589`), а на приёме строит её из `quoteText`/`replyMedia`.
- Исходящие атрибуты фильтруются белым списком (`EnqueueMessage.swift:253-306`), а после подтверждения сервером атрибуты сообщения заменяются серверными (`ApplyUpdateMessage.swift:258-263`): локальный атрибут до получателя не доедет и у отправителя не выживет. Данные должны ехать в самом сообщении.
- Сущности текста: `textUrl` красится цветом ссылки без подчёркивания (`StringWithAppliedEntities.swift:230-232, 292-304`); `customEmoji` с неизвестным `document_id` рисуется **пустым местом** размером с эмодзи (`TextNodeWithEntities.swift:177-215`, `EmojiTextAttachmentView.swift:524`). Превью ссылок отключается флагом `no_webpage` через `OutgoingContentInfoMessageAttribute([.disableLinkPreviews])` (`ChatControllerNode.swift:5296-5302`, `PendingMessageManager.swift:1795-1797`). При отправке обрезаются только пробелы, табы, переводы строки и U+200C (`ChatTextInputAttributes.swift:1102, 1135`); U+200B остаётся.

Во всех вариантах сами данные одинаковы: тип (объект/точка), точка касания и рамка, нормализованные 0…1 относительно оригинала, плюс версия формата. Предлагаю упаковать их в короткую строку/байты с магическим префиксом `VQ1`.

### Вариант A. Поле `poll_option` ответа как контейнер байтов
Кладём закодированную область в `innerSubject = .pollOption(bytes)`; существующий код отправляет её в `poll_option`, получатель получает её в `innerSubject`, наш UI распознаёт префикс.
- Плюсы: данные едут в самом заголовке ответа, где им и место; текст сообщения чистый; **ни одной правки в TelegramCore** (используется готовый путь); в обычном Telegram iOS заголовок ответа на фото без опроса не находит вариант и показывает обычный ответ (`ChatMessageReplyInfoNode.swift:450` требует `TelegramMediaPoll`).
- Минусы: сервер может отвергнуть `poll_option` для сообщения без опроса — неизвестно, нужна одна пробная отправка на M3; другие официальные клиенты (Android, Desktop) могут вести себя иначе на непонятном `poll_option` — проверить на телефоне Ники; это злоупотребление полем, в продакшене недопустимо.

### Вариант B. Невидимая ссылка в тексте
К тексту ответа добавляется символ нулевой ширины (U+200B) с сущностью `textUrl`, где URL несёт координаты, например `https://t.me/visual-quote#VQ1;o;0.512,0.377;0.41,0.30,0.22,0.19`; превью ссылки отключается `disableLinkPreviews`.
- Плюсы: сервер точно примет (обычные сущности); в обычном Telegram сообщение выглядит как обычный ответ: символ нулевой ширины не виден, подчёркивания нет; тоже без правок TelegramCore (сущности собираются в UI при отправке, читаются в UI при показе).
- Минусы: в тексте появляется невидимый символ (копируется вместе с текстом); долгое нажатие точно по невидимому символу теоретически открывает ссылку; требует непустого текста ответа (в v0 текст есть всегда; пустой текст подставлять нельзя — пробел обрежется); риск, что какой-то клиент покажет пустой «хвост» ссылки.

### Вариант C. Сущность custom emoji с координатами в `document_id`
На эмодзи-символ (например 📍) вешается `messageEntityCustomEmoji`, а 64 бита `document_id` кодируют x, y, w, h по 16 бит.
- Плюсы: компактно, без URL, сервер примет.
- Минусы: в обычном Telegram на месте эмодзи будет **пустой промежуток** (файл не резолвится, слой остаётся пустым) — это и есть «мусор», которого требование 2.10 не допускает; нет места для точки касания и типа; не рекомендую.

### Что было бы в продакшене
Новый случай `EngineMessageReplyInnerSubject.imageRegion` и поле в `inputReplyToMessage`/`messageReplyHeader` рядом с `todo_item_id`/`poll_option`, например `quote_region:flags.N?ImageRegion` (тип с четырьмя нормализованными координатами и точкой). Клиентская часть при этом совпадает с прототипом один в один: меняется только кодирование в `PendingMessageManager`/`StoreMessage_Telegram`. Это нужно прямо написать в README (раздел 2.11 задания).

Выбор между A и B — за Никой после M1; моё предложение: реализовать кодек один раз, транспорт сделать сменяемым, на M3 сначала пробовать A (одна отправка покажет, принимает ли сервер), при отказе — B.

## 6. Точки встраивания и объём

Принцип: новый код в новом модуле `submodules/TelegramUI/Components/VisualQuote` (модель `VisualQuote`, кодек транспорта, нода подсветки, рендер фрагмента), в существующих файлах — тонкие точки входа. TelegramCore не трогаем: оба рабочих транспорта обходятся без него.

| # | Что | Где подключать | Объём |
| --- | --- | --- | --- |
| 1 | Модель и кодек | новый модуль | ~1 день |
| 2 | Жест в галерее: долгое нажатие по фото | `ZoomableContentGalleryItemNode` — задать `longTap` у существующего `TapLongTapOrDoubleTapGestureRecognizer` (`:46`) или обработать `.longTap` в `contentTap` (`:104`); переопределение в `ChatImageGalleryItemNode`; координата → нормализованная точка через `scrollNode.view.convert` (`:88`) | 0.5 дня |
| 3 | Выделение: Vision | вызов `cutoutImage(from: imageNode.image, target: .point(p))` из `ImageObjectSeparation` (модуль уже подключён в TelegramUI); проверка `cutoutAvailability` (в симуляторе качает модель); фолбэк — кольцо в точке | 1 день |
| 4 | Подсветка | оверлей-нода поверх `imageNode` по образцу `RecognizedContentContainer` (`ChatImageGalleryItem.swift:447`); контур из маски — `getPathFromMaskImage` из `StickerCutoutOutlineView` (вынести в общий код без изменения оригинала), спокойный вариант свечения; хаптика `HapticFeedback().impact(.light)`; **2 варианта на выбор Ники** | 1.5 дня |
| 5 | Кнопка «Reply» | в стеклянную группу футера `ChatItemGalleryFooterContentNode.updateLayout` (`:1334-1443`) или отдельная кнопка над футером; действие — копия меню «Reply» (`ChatImageGalleryItem.swift:787-804`) с передачей области через `MessageHighlight.subject` / новое поле; **варианты на выбор Ники** | 1 день |
| 6 | Композер: панель ответа с фрагментом | `ChatInterfaceState.ReplyMessageSubject` (добавить область рядом с `innerSubject`, модуль ChatInterfaceState), `ChatInputMessageAccessoryPanel.Contents.Reply` — показать фрагмент (вернуть закомментированную миниатюру `:489-510`, но с кропом) | 1 день |
| 7 | Отправка | `ChatControllerNode.sendCurrentMessage` (`:5024`): кодирование области в транспорт (A: `innerSubject = .pollOption(bytes)`; B: сущность + `disableLinkPreviews`) | 0.5 дня |
| 8 | Получатель: заголовок | `ChatMessageBubbleItemNode.swift:2149-2171, 3030-3046` → `ChatMessageReplyInfoNode`: декодировать область из сообщения, рисовать увеличенный фрагмент с подсветкой вместо миниатюры `imageSide`; состояния «оригинал не загружен» (сначала миниатюра), «оригинал удалён»; **2 варианта размера на выбор Ники** | 2 дня |
| 9 | Переход по нажатию | `ChatMessageBubbleItemNode.swift:5990` → `navigateToMessage(... subject:)` → открыть галерею на сообщении и приблизить к области: `scrollNode.view.zoom(to:)` после `activateAsInitial()` (`GalleryItemNode.swift:88`) с учётом сброса зума в `resetScrollViewContents`; короткая подсветка | 1 день |
| 10 | Флаг в Debug Settings, строки, VoiceOver | `ExperimentalUISettings` + `DebugController` (раздел 3); `en.lproj/Localizable.strings`; `accessibilityLabel` по образцу `ReplyAccessoryPanelNode.swift:326-332` | 0.5 дня |
| 11 | Проверка тем, README, сборка с нуля | — | 1.5 дня |

Итого ориентировочно 11–12 рабочих дней чистой разработки без учёта согласований; каждая правка сопровождается полной сборкой и проверкой в симуляторе.

## 7. Открытые вопросы для Ники

1. Транспорт координат: A (`poll_option`) или B (невидимая ссылка). Предложение — сначала пробовать A на M3.
2. Для Vision в симуляторе нужен залогиненный аккаунт (загрузка модели из канала). Вопрос входа в аккаунты остаётся блокером для M2.
3. Где жить кнопке «Reply»: в стеклянном футере среди существующих кнопок или отдельной кнопкой рядом с выделением. Покажу оба варианта скриншотами на M2.
