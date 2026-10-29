// Bizi in the POS: its words and the cashier’s questions (EN / KM), one list for every POS kind.
// The button names in the steps are the ones on the POS screens — keep them the same when a screen changes.

const posBiziText = <String, Map<String, String>>{
  'en': {
    'ph': 'Ask how to… (printer, shift, void…)',
    'close': 'Close',
    'says': 'Bizi says',
    'questions': 'Questions',
    'howTo': 'How to',
    'tapSteps': 'Tap to see the steps',
    'quick': 'Quick',
    'doIt': 'Do it now',
    'dark': 'Dark mode',
    'light': 'Light mode',
    'none': "I don’t know that one yet — ask the owner, or the BizHub team in the BizHub app.",
    'tg_new': '{n} new Telegram orders waiting',
    'tg_new1': '1 new Telegram order waiting',
    'waited': 'The oldest has waited {min} min',
  },
  'km': {
    'ph': 'សួររបៀប… (ម៉ាស៊ីនបោះពុម្ព វេន លុប…)',
    'close': 'បិទ',
    'says': 'Bizi ប្រាប់',
    'questions': 'សំណួរ',
    'howTo': 'របៀបធ្វើ',
    'tapSteps': 'ចុចដើម្បីមើលជំហាន',
    'quick': 'រហ័ស',
    'doIt': 'ធ្វើឥឡូវ',
    'dark': 'ម៉ូដងងឹត',
    'light': 'ម៉ូដភ្លឺ',
    'none': 'ខ្ញុំមិនទាន់ដឹងរឿងនេះទេ — សួរម្ចាស់ ឬក្រុម BizHub ក្នុងកម្មវិធី BizHub។',
    'tg_new': 'ការកម្ម៉ង់ Telegram ថ្មី {n} កំពុងរង់ចាំ',
    'tg_new1': 'ការកម្ម៉ង់ Telegram ថ្មី 1 កំពុងរង់ចាំ',
    'waited': 'ការកម្ម៉ង់ចាស់ជាងគេរង់ចាំ {min} នាទី',
  },
};

// the questions for this POS kind
List<Map> posHelpFor(String kind) => posHelp.where((a) => (a['kinds'] as List).contains(kind)).toList();

const _rmg = ['restaurant', 'mart', 'guest_house'];
const _all = ['restaurant', 'mart', 'guest_house', 'tg_store', 'stamp_card', 'event'];

const posHelp = <Map<String, Object>>[
  {
    'id': 'r_shift',
    'kinds': ['restaurant'],
    'popular': true,
    'words': 'shift open close cash drawer count money report end of day · វេន បើកវេន បិទវេន សាច់ប្រាក់ ថត',
    'en': {
      'q': 'How do I open or close a shift?',
      'steps': [
        'After your PIN, “Open shift”: count the “Cash in USD” and “Cash in riel”, then “Start selling”.',
        'To close: ☰ → “Close shift” — it shows the bills, sales, discounts and what should be in the drawer.',
        'Count the USD and riel, then “Close shift and send” (it works offline too; open bills move to the next shift).',
        '“Print shift report”, then “Done”.',
      ],
    },
    'km': {
      'q': 'តើបើក ឬបិទវេនយ៉ាងម៉េច?',
      'steps': [
        'ក្រោយ PIN “បើកវេន”៖ រាប់ “សាច់ប្រាក់ដុល្លារ” និង “សាច់ប្រាក់រៀល” រួច “ចាប់ផ្តើមលក់”។',
        'ដើម្បីបិទ៖ ☰ → “បិទវេន” — វាបង្ហាញវិក្កយបត្រ ការលក់ បញ្ចុះតម្លៃ និង “គួរមានក្នុងថត”។',
        'រាប់ដុល្លារ និងរៀល រួច “បិទវេន និងផ្ញើ” (ដំណើរការពេលគ្មានអ៊ីនធឺណិតផងដែរ; វិក្កយបត្រនៅបើកទៅវេនបន្ទាប់)។',
        '“ព្រីនរបាយការណ៍វេន” រួច “រួចរាល់”។',
      ],
    },
  },
  {
    'id': 'm_shift',
    'kinds': ['mart'],
    'popular': true,
    'words': 'shift open close cash drawer count money in out end of day · វេន បើកវេន បិទវេន លុយចូល លុយចេញ',
    'en': {
      'q': 'How do I open or close a shift?',
      'steps': [
        'Open: “Open your shift” → “Start shift” (when the shop uses shifts).',
        'Money put in or taken out during the day: ☰ → “Money in” / “Money out”.',
        'Close: ☰ → “Close shift” — count the cash; it shows what “Should be” there and the difference.',
        'Opening and closing need internet; without it: “No internet — sell now, open the shift later”.',
      ],
    },
    'km': {
      'q': 'តើបើក ឬបិទវេនយ៉ាងម៉េច?',
      'steps': [
        'បើក៖ “បើកវេនរបស់អ្នក” → “ចាប់ផ្តើមវេន” (ពេលហាងប្រើវេន)។',
        'លុយដាក់ចូល ឬដកចេញក្នុងថ្ងៃ៖ ☰ → “លុយចូល” / “លុយចេញ”។',
        'បិទ៖ ☰ → “បិទវេន” — រាប់សាច់ប្រាក់; វាបង្ហាញ “គួរមាន” និងភាពខុសគ្នា។',
        'ការបើក និងបិទត្រូវការអ៊ីនធឺណិត; បើគ្មាន៖ “គ្មានអ៊ីនធឺណិត — លក់សិន បើកវេនពេលក្រោយ”។',
      ],
    },
  },
  {
    'id': 'r_lock',
    'kinds': ['restaurant'],
    'words': 'switch staff lock log out pin change cashier · ប្តូរបុគ្គលិក ចាក់សោ PIN',
    'en': {
      'q': 'How do I switch staff (lock the screen)?',
      'steps': ['☰ → “Switch staff” — the shift stays open.', 'The next person types their PIN (it works offline).'],
    },
    'km': {
      'q': 'តើប្តូរបុគ្គលិក (ចាក់សោអេក្រង់) យ៉ាងម៉េច?',
      'steps': ['☰ → “ប្តូរបុគ្គលិក” — វេននៅតែបើក។', 'អ្នកបន្ទាប់វាយ PIN របស់ខ្លួន (ដំណើរការពេលគ្មានអ៊ីនធឺណិត)។'],
    },
  },
  {
    'id': 'm_lock',
    'kinds': ['mart', 'guest_house', 'tg_store', 'stamp_card'],
    'words': 'switch staff lock log out pin change cashier · ប្តូរបុគ្គលិក ចាក់សោ PIN',
    'en': {
      'q': 'How do I lock the screen (switch staff)?',
      'steps': ['Mini mart / guest house: ☰ → “Lock”. Telegram Store and stamp desk: the lock icon at the top.', 'The next person types their PIN (the stamp desk: the desk PIN).'],
    },
    'km': {
      'q': 'តើចាក់សោអេក្រង់ (ប្តូរបុគ្គលិក) យ៉ាងម៉េច?',
      'steps': ['ម៉ាត / ផ្ទះសំណាក់៖ ☰ → “ចាក់សោ”។ ហាង Telegram និងតុបោះត្រា៖ រូបសោនៅខាងលើ។', 'អ្នកបន្ទាប់វាយ PIN របស់ខ្លួន (តុបោះត្រា៖ PIN តុ)។'],
    },
  },
  {
    'id': 'r_void',
    'kinds': ['restaurant'],
    'popular': true,
    'words': 'void cancel delete remove item order bill mistake refund · លុប លុបមុខម្ហូប លុបការកុម្ម៉ង់ មូលហេតុ',
    'en': {
      'q': 'How do I cancel an item or an order?',
      'steps': [
        'Tap the item line. Still “New”: use − / + or “Cancel item”.',
        'Already sent to the kitchen: write “Why cancel?” (optional) → “Cancel item” — the reason stays on the bill.',
        'The whole order: “…” at the top → “Cancel order”.',
        'A paid bill can’t be refunded on the POS — ask the owner.',
      ],
    },
    'km': {
      'q': 'តើលុបមុខម្ហូប ឬការកុម្ម៉ង់យ៉ាងម៉េច?',
      'steps': [
        'ចុចលើបន្ទាត់មុខម្ហូប។ នៅ “ថ្មី”៖ ប្រើ − / + ឬ “លុបមុខម្ហូប”។',
        'បានផ្ញើទៅផ្ទះបាយរួច៖ សរសេរ “មូលហេតុលុបចោល (មិនចាំបាច់)” → “លុបមុខម្ហូប” — មូលហេតុនៅលើវិក្កយបត្រ។',
        'ការកុម្ម៉ង់ទាំងមូល៖ “…” នៅខាងលើ → “លុបការកុម្ម៉ង់”។',
        'វិក្កយបត្រដែលបានបង់ មិនអាចសងប្រាក់វិញលើ POS ទេ — សួរម្ចាស់។',
      ],
    },
  },
  {
    'id': 'm_void',
    'kinds': ['mart'],
    'popular': true,
    'words': 'void cancel delete remove item sale receipt mistake refund clear cart · លុបចោល សម្អាត កន្ត្រក',
    'en': {
      'q': 'How do I remove an item or void a sale?',
      'steps': [
        'In the cart: tap − down to 0, or the trash icon “Clear” → “Clear the cart?”.',
        'A paid sale: “Sales” → tap the sale → “Void” → a reason (optional) → Void.',
        'Only managers see “Void”. There is no partial refund.',
      ],
    },
    'km': {
      'q': 'តើដកទំនិញ ឬលុបការលក់យ៉ាងម៉េច?',
      'steps': [
        'ក្នុងកន្ត្រក៖ ចុច − រហូតដល់ 0 ឬរូបធុងសំរាម “សម្អាត” → “សម្អាតកន្ត្រក?”។',
        'ការលក់ដែលបានបង់៖ “ការលក់” → ចុចលើការលក់ → “លុបចោល” → មូលហេតុ (មិនចាំបាច់) → លុបចោល។',
        'មានតែអ្នកគ្រប់គ្រងទេដែលឃើញ “លុបចោល”។ មិនមានការសងប្រាក់មួយផ្នែកទេ។',
      ],
    },
  },
  {
    'id': 'printer',
    'kinds': _rmg,
    'popular': true,
    'words': "printer print receipt not printing doesn’t print bluetooth wifi lan ip paper test 58 80 · ម៉ាស៊ីនព្រីន ព្រីន បោះពុម្ព ក្រដាស ព្រីនសាកល្បង",
    'en': {
      'q': "The printer doesn’t print — what do I do?",
      'steps': [
        '☰ → “Printers”: choose “Bluetooth printer” (pair it in the phone’s settings first), “Wi-Fi / LAN printer” (type its IP) or “Phone print window”.',
        'Choose the paper width (80 or 58 mm) and tap “Print a test page”.',
        'Still nothing: Bluetooth on? “Nearby devices” allowed? For Wi-Fi: same Wi-Fi as the printer, right IP address?',
        'Bluetooth and Wi-Fi printing need the owner’s “Printing” add-on — the phone print window always works.',
      ],
    },
    'km': {
      'q': 'ម៉ាស៊ីនព្រីនមិនព្រីន — តើធ្វើម៉េច?',
      'steps': [
        '☰ → “ម៉ាស៊ីនព្រីន”៖ ជ្រើស “ម៉ាស៊ីនព្រីន Bluetooth” (ផ្គូផ្គងក្នុងការកំណត់ទូរស័ព្ទជាមុន) “Wi-Fi / LAN printer” (វាយ IP) ឬ “ផ្ទាំងព្រីនរបស់ទូរស័ព្ទ”។',
        'ជ្រើសទំហំក្រដាស (80 ឬ 58 mm) ហើយចុច “ព្រីនសាកល្បង”។',
        'នៅតែមិនចេញ៖ Bluetooth បើកទេ? អនុញ្ញាត “Nearby devices” ទេ? Wi-Fi៖ Wi-Fi ដូចម៉ាស៊ីនព្រីន ហើយ IP ត្រូវទេ?',
        'ការព្រីនតាម Bluetooth និង Wi-Fi ត្រូវការមុខងារបន្ថែម “បោះពុម្ព” របស់ម្ចាស់ — ផ្ទាំងព្រីនរបស់ទូរស័ព្ទប្រើបានជានិច្ច។',
      ],
    },
  },
  {
    'id': 'ts_printer',
    'kinds': ['tg_store', 'event'],
    'words': 'printer print ticket order not printing bluetooth wifi test · ម៉ាស៊ីនបោះពុម្ព បោះពុម្ព ម៉ាស៊ីនព្រីនសំបុត្រ',
    'en': {
      'q': 'How do I set up the printer?',
      'steps': [
        'Telegram Store: ⋮ → “Order printer”. Event door: ⋮ → “Ticket printer”.',
        'Choose Bluetooth (pair it in the phone’s settings first), Wi-Fi / LAN (its IP) or the phone print window, then “Print a test page”.',
        'Telegram Store: “Print” on an order; a ticket prints on Accept when auto-print is on.',
      ],
    },
    'km': {
      'q': 'តើរៀបចំម៉ាស៊ីនបោះពុម្ពយ៉ាងម៉េច?',
      'steps': [
        'ហាង Telegram៖ ⋮ → “ម៉ាស៊ីនបោះពុម្ពការកម្ម៉ង់”។ ទ្វារកម្មវិធី៖ ⋮ → “ម៉ាស៊ីនព្រីនសំបុត្រ”។',
        'ជ្រើស Bluetooth (ផ្គូផ្គងក្នុងការកំណត់ទូរស័ព្ទជាមុន) Wi-Fi / LAN (IP) ឬផ្ទាំងព្រីនរបស់ទូរស័ព្ទ រួច “ព្រីនសាកល្បង”។',
        'ហាង Telegram៖ “បោះពុម្ព” លើការកម្ម៉ង់; សំបុត្រព្រីនពេលទទួល បើបើកការព្រីនដោយស្វ័យប្រវត្តិ។',
      ],
    },
  },
  {
    'id': 'r_offline',
    'kinds': ['restaurant', 'mart', 'guest_house'],
    'popular': true,
    'words': 'offline no internet wifi down sync send waiting not sent connection · គ្មានអ៊ីនធឺណិត ផ្ញើឥឡូវ រង់ចាំ',
    'en': {
      'q': 'No internet — can I keep selling?',
      'steps': [
        'Yes: sales are kept on this device and sent when the internet is back.',
        'The pill at the top shows Online / Offline / “{n} waiting” — tap it to send now (or ☰ → “Sync now”).',
        'The owner may limit how long the POS sells offline (a restaurant: 24 hours by default).',
      ],
    },
    'km': {
      'q': 'គ្មានអ៊ីនធឺណិត — តើលក់បន្តបានទេ?',
      'steps': [
        'បាន៖ ការលក់រក្សាទុកលើឧបករណ៍នេះ ហើយផ្ញើពេលមានអ៊ីនធឺណិតវិញ។',
        'ផ្លាកនៅខាងលើបង្ហាញ Online / Offline / “រង់ចាំ {n}” — ចុចវាដើម្បីផ្ញើឥឡូវ (ឬ ☰ → “ផ្ញើឥឡូវ”)។',
        'ម្ចាស់អាចកំណត់រយៈពេលលក់ពេលគ្មានអ៊ីនធឺណិត (ភោជនីយដ្ឋាន៖ 24 ម៉ោងតាមលំនាំដើម)។',
      ],
    },
  },
  {
    'id': 'ev_offline',
    'kinds': ['event'],
    'popular': true,
    'words': 'offline no internet scans send sync connection · គ្មានអ៊ីនធឺណិត',
    'en': {
      'q': 'No internet — can I keep scanning?',
      'steps': ['Yes: it says “Offline — checking on this phone” and keeps checking tickets.', 'It shows how many scans are left to send and sends them by itself every 20 seconds once online.'],
    },
    'km': {
      'q': 'គ្មានអ៊ីនធឺណិត — តើស្កេនបន្តបានទេ?',
      'steps': ['បាន៖ វាបង្ហាញថា Offline ហើយបន្តពិនិត្យសំបុត្រលើទូរស័ព្ទនេះ។', 'វាបង្ហាញចំនួនស្កេនដែលនៅត្រូវផ្ញើ ហើយផ្ញើដោយខ្លួនឯងរៀងរាល់ 20 វិនាទីពេលមានអ៊ីនធឺណិត។'],
    },
  },
  {
    'id': 'r_discount',
    'kinds': ['restaurant', 'mart'],
    'words': 'discount percent price off promo coupon member · បញ្ចុះតម្លៃ កូដបញ្ចុះ សមាជិក',
    'en': {
      'q': 'How do I give a discount?',
      'steps': [
        'Restaurant: the whole order — “…” → “Discount”: a % (5 / 10 / 15 / 20 / 50) or an amount → “Apply”. One item: tap its line → “Discount on this item”.',
        'Mini mart: the “Discount” pill on the cart (\$ / ៛ or %) → “Apply”; a promo code: “Coupon”; a member: “Member”.',
        'The owner can cap discounts; promotions apply by themselves.',
      ],
    },
    'km': {
      'q': 'តើផ្តល់ការបញ្ចុះតម្លៃយ៉ាងម៉េច?',
      'steps': [
        'ភោជនីយដ្ឋាន៖ ការកុម្ម៉ង់ទាំងមូល — “…” → “បញ្ចុះតម្លៃ”៖ % (5 / 10 / 15 / 20 / 50) ឬ “ចំនួន” → “អនុវត្ត”។ មុខតែមួយ៖ ចុចបន្ទាត់ → “បញ្ចុះតម្លៃមុខនេះ”។',
        'ម៉ាត៖ ប៊ូតុង “បញ្ចុះតម្លៃ” លើកន្ត្រក (\$ / ៛ ឬ %) → “យក”; កូដ៖ “កូដបញ្ចុះ”; សមាជិក៖ “សមាជិក”។',
        'ម្ចាស់អាចកំណត់ការបញ្ចុះតម្លៃអតិបរមា; ប្រូម៉ូសិនដំណើរការដោយខ្លួនឯង។',
      ],
    },
  },
  {
    'id': 'ts_orders',
    'kinds': ['tg_store'],
    'popular': true,
    'words': 'accept order reject ready done paid on the way delivery riders new order board · ទទួល បដិសេធ រួចរាល់ បានបង់ កំពុងដឹក ការកម្ម៉ង់ថ្មី',
    'en': {
      'q': 'How do I handle a new order?',
      'steps': [
        'In “New”: “Accept”, or “15 min” / “30 min” to say when it’s ready, or “Reject” (the customer sees the reason).',
        'Then “Ready” (or “On the way” for delivery) → “Done”.',
        '“Mark paid” when the money is in; “Send to riders” for delivery riders.',
      ],
    },
    'km': {
      'q': 'តើធ្វើយ៉ាងណាជាមួយការកម្ម៉ង់ថ្មី?',
      'steps': [
        'ក្នុង “ថ្មី”៖ “ទទួល” ឬ “15 នាទី” / “30 នាទី” ដើម្បីប្រាប់ពេលរួចរាល់ ឬ “បដិសេធ” (អតិថិជនឃើញមូលហេតុ)។',
        'រួច “រួចរាល់” (ឬ “កំពុងដឹក” សម្រាប់ការដឹក) → “រួចរាល់”។',
        '“បានបង់” ពេលទទួលប្រាក់; “Send to riders” សម្រាប់អ្នកដឹក។',
      ],
    },
  },
  {
    'id': 'ts_sound',
    'kinds': ['tg_store'],
    'popular': true,
    'words': 'sound chime bell ring alert noise mute quiet loud new order banner · សំឡេង បើកសំឡេង បិទសំឡេង',
    'en': {
      'q': 'How do I turn the order sound on or off?',
      'steps': ['Tap the bell at the top: “Sound on” / “Sound off”.', 'While a new order waits, the chime rings every 6 seconds and a “New order” banner shows; the list refreshes every 5 seconds.'],
    },
    'km': {
      'q': 'តើបើក ឬបិទសំឡេងការកម្ម៉ង់យ៉ាងម៉េច?',
      'steps': ['ចុចរូបកណ្តឹងនៅខាងលើ៖ “បើកសំឡេង” / “បិទសំឡេង”។', 'ពេលការកម្ម៉ង់ថ្មីរង់ចាំ សំឡេងរោទ៍រៀងរាល់ 6 វិនាទី ហើយបង្ហាញ “ការកម្ម៉ង់ថ្មី”; បញ្ជីធ្វើបច្ចុប្បន្នភាពរៀងរាល់ 5 វិនាទី។'],
    },
  },
  {
    'id': 'gh_checkin',
    'kinds': ['guest_house'],
    'popular': true,
    'words': 'check in check out guest arrival departure walk-in room payment · ចូលស្នាក់នៅ ចេញ ភ្ញៀវមកដល់ ភ្ញៀវចេញ ភ្ញៀវដើរចូល',
    'en': {
      'q': 'How do I check a guest in or out?',
      'steps': [
        '“Today” → “Arrivals” → “Check in” (it shows from the arrival day).',
        'No booking: “Walk-in”, or tap a free room.',
        '“Departures” → “Check out”; money owed: “Take payment” (or “Check out anyway”).',
      ],
    },
    'km': {
      'q': 'តើឱ្យភ្ញៀវចូលស្នាក់នៅ ឬចេញយ៉ាងម៉េច?',
      'steps': ['“ថ្ងៃនេះ” → “ភ្ញៀវមកដល់” → “ចូលស្នាក់នៅ” (បង្ហាញចាប់ពីថ្ងៃមកដល់)។', 'គ្មានការកក់៖ “ភ្ញៀវដើរចូល” ឬចុចលើបន្ទប់ទំនេរ។', '“ភ្ញៀវចេញ” → “ចេញ”; នៅជំពាក់៖ “ទទួលប្រាក់” (ឬ “ចេញទោះយ៉ាងណា”)។'],
    },
  },
  {
    'id': 'sc_stamp',
    'kinds': ['stamp_card'],
    'popular': true,
    'words': 'stamp give add card scan customer phone reward redeem free next · បោះត្រា ស្កេនកាត ផ្តល់ រង្វាន់ អតិថិជនបន្ទាប់',
    'en': {
      'q': 'How do I give a stamp or a reward?',
      'steps': [
        '“Scan card”, or search the card number, phone or name.',
        '“+1 stamp” (or +2 / +3 / +5, up to the most per visit).',
        'A reward is ready: tap the green “Give …” button.',
        '“Next customer”.',
      ],
    },
    'km': {
      'q': 'តើបោះត្រា ឬផ្តល់រង្វាន់យ៉ាងម៉េច?',
      'steps': ['“ស្កេនកាត” ឬស្វែងរកលេខកាត លេខទូរស័ព្ទ ឬឈ្មោះ។', '“+1 ត្រា” (ឬ +2 / +3 / +5 តាមចំនួនអតិបរមាក្នុងមួយដង)។', 'រង្វាន់រួចរាល់៖ ចុចប៊ូតុងបៃតង “ផ្តល់ …”។', '“អតិថិជនបន្ទាប់”។'],
    },
  },
  {
    'id': 'ev_scan',
    'kinds': ['event'],
    'popular': true,
    'words': 'scan ticket check door green amber red already used cancelled code · ស្កេន សំបុត្រ ពិនិត្យ បានប្រើរួចហើយ',
    'en': {
      'q': 'What do the scan colours mean?',
      'steps': [
        'Scan with the camera, or “Type the ticket code” → “Check”.',
        'Green “Welcome in!” — let them in. Amber “Already used” — it shows when and by whom.',
        'Red — cancelled, for another event or time, or not a ticket. Tap to scan the next one.',
      ],
    },
    'km': {
      'q': 'តើពណ៌ពេលស្កេនមានន័យអ្វី?',
      'steps': [
        'ស្កេនដោយកាមេរ៉ា ឬវាយលេខកូដសំបុត្រ → “ពិនិត្យ”។',
        'បៃតង “សូមស្វាគមន៍!” — ឱ្យចូល។ លឿងទុំ “បានប្រើរួចហើយ” — បង្ហាញពេល និងអ្នកដែលបានប្រើ។',
        'ក្រហម — បានបោះបង់ សម្រាប់កម្មវិធី ឬម៉ោងផ្សេង ឬ “មិនមែនជាសំបុត្រ”។ ចុចដើម្បីស្កេនបន្ទាប់។',
      ],
    },
  },
  {
    'id': 'display',
    'kinds': ['mart', 'guest_house'],
    'words': 'customer display second screen monitor show customer total qr · អេក្រង់អតិថិជន',
    'en': {
      'q': 'How do I show the customer screen?',
      'steps': [
        'It needs the owner’s “Customer screen” add-on.',
        'A dual-screen Android terminal shows it by itself. A Mac / PC with a second monitor: Printers → “Customer screen on the second monitor”.',
        'It shows the cart and total, the payment QR, then thank you.',
      ],
    },
    'km': {
      'q': 'តើបង្ហាញអេក្រង់អតិថិជនយ៉ាងម៉េច?',
      'steps': [
        'ត្រូវការមុខងារបន្ថែម “អេក្រង់អតិថិជន” របស់ម្ចាស់។',
        'ម៉ាស៊ីន Android អេក្រង់ពីរ បង្ហាញដោយខ្លួនឯង។ Mac / PC មានអេក្រង់ទីពីរ៖ ម៉ាស៊ីនព្រីន → “Customer screen on the second monitor”។',
        'វាបង្ហាញកន្ត្រក និងសរុប QR បង់ប្រាក់ រួចអរគុណ។',
      ],
    },
  },
  {
    'id': 'look',
    'kinds': _all,
    'words': 'language khmer english dark mode light appearance theme settings · ភាសា ខ្មែរ អង់គ្លេស រូបរាង ងងឹត ភ្លឺ',
    'en': {
      'q': 'How do I change the language or dark mode?',
      'steps': ['☰ or ⋮ → the language row (“ភាសាខ្មែរ” / “English”) and “Appearance”: Light / Dark / Same as the phone.', 'Quicker: here in Bizi, “Dark mode” and the language are under “Quick”.'],
    },
    'km': {
      'q': 'តើប្តូរភាសា ឬម៉ូដងងឹតយ៉ាងម៉េច?',
      'steps': ['☰ ឬ ⋮ → ជួរភាសា (“ភាសាខ្មែរ” / “English”) និង “រូបរាង”៖ ភ្លឺ / ងងឹត / “តាមទូរស័ព្ទ”។', 'លឿនជាង៖ នៅទីនេះក្នុង Bizi “ម៉ូដងងឹត” និងភាសានៅក្រោម “រហ័ស”។'],
    },
  },
  {
    'id': 'unlink',
    'kinds': _all,
    'words': 'unlink disconnect unpair device screen phone link another business shop code change · ផ្តាច់ឧបករណ៍នេះ ផ្តាច់ ភ្ជាប់ លេខកូដ',
    'en': {
      'q': 'How do I unlink this device or link it to another shop?',
      'steps': [
        'Restaurant: ☰ → “Unlink this device” (a manager PIN; unsent sales are sent first). Mini mart / guest house: lock first, then “Unlink this device” on the PIN screen.',
        'Telegram Store: ⋮ → “Disconnect this screen”. Event: ⋮ → “Unpair this phone”. Stamp desk: ⋮ → “Unlink this device”.',
        'To link again: choose the POS and type the owner’s 6-digit code (the owner makes it on the website or the BizHub app).',
      ],
    },
    'km': {
      'q': 'តើផ្តាច់ឧបករណ៍នេះ ឬភ្ជាប់ទៅហាងផ្សេងយ៉ាងម៉េច?',
      'steps': [
        'ភោជនីយដ្ឋាន៖ ☰ → “ផ្តាច់ឧបករណ៍នេះ” (PIN អ្នកគ្រប់គ្រង; ការលក់មិនទាន់ផ្ញើ ត្រូវផ្ញើជាមុន)។ ម៉ាត / ផ្ទះសំណាក់៖ ចាក់សោជាមុន រួច “ផ្តាច់ឧបករណ៍នេះ” លើអេក្រង់ PIN។',
        'ហាង Telegram៖ ⋮ → “ផ្តាច់អេក្រង់នេះ”។ កម្មវិធី៖ ⋮ → “ផ្តាច់ទូរស័ព្ទនេះ”។ តុបោះត្រា៖ ⋮ → “ផ្តាច់ឧបករណ៍នេះ”។',
        'ដើម្បីភ្ជាប់វិញ៖ ជ្រើស POS ហើយវាយលេខកូដ ៦ ខ្ទង់របស់ម្ចាស់ (ម្ចាស់បង្កើតនៅលើគេហទំព័រ ឬកម្មវិធី BizHub)។',
      ],
    },
  },
];
