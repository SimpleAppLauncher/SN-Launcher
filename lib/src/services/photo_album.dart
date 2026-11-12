/// The photo albums the launcher can put behind the clock.
///
/// Three of them, and the difference between them is what the photograph
/// actually is, not how it is coloured:
///
///  * **Landscape** — what the launcher shipped with. Curated nature
///    photographs, and the only album that also discovers new ones at runtime.
///  * **Racing cars** — Formula One, Le Mans / WEC and rally machinery.
///    Curated only: a Commons category is not vetted for "is this actually a
///    racing car", so the hand-checked list is the whole truth here.
///  * **Fernando Alonso** — the driver's whole career, Renault through
///    McLaren, Ferrari and Aston Martin. Half of it is him in the car, half is
///    him as the subject — the podiums, the press conferences, the champagne.
library;

/// A photograph the rotation is allowed to use.
///
/// Not a live search. Every entry is a specific Wikimedia Commons file that has
/// been looked at and judged: public domain, CC0 or CC-BY, and shaped so that
/// a 16:9 wall display does not have to crop a person's face off.
class AlbumPhoto {
  const AlbumPhoto(this.title, this.author);
  final String title;

  /// The name to put on screen.
  ///
  /// Overrides whatever the Commons `Artist` field says. That field routinely
  /// contains markup, agency boilerplate, or — in one case we picked — a dead
  /// link, and this string is rendered next to the album title on the user's
  /// wall, so it has to read like a person's name.
  final String author;
}

/// The background albums.
enum PhotoAlbum {
  landscape,
  racing,
  alonso;

  /// What the Settings picker calls this.
  String get label => switch (this) {
        PhotoAlbum.landscape => 'Landscape',
        PhotoAlbum.racing => 'Cars',
        PhotoAlbum.alonso => 'Fernando Alonso',
      };

  /// The caption that sits in the bottom-right corner of the home screen.
  ///
  /// Landscape keeps the word that was measured off a real Nest Hub
  /// photograph. The other two name themselves.
  String get caption => switch (this) {
        PhotoAlbum.landscape => 'Recent highlights',
        PhotoAlbum.racing => 'Racing cars',
        PhotoAlbum.alonso => 'Fernando Alonso',
      };

  /// The photograph that paints before anything has been downloaded.
  String get heroAsset => switch (this) {
        PhotoAlbum.landscape => 'assets/photo/landscape.jpg',
        PhotoAlbum.racing => 'assets/photo/racing.jpg',
        PhotoAlbum.alonso => 'assets/photo/alonso.jpg',
      };

  /// The sidecar JSON that carries the hero's licence.
  String get heroCreditAsset => switch (this) {
        PhotoAlbum.landscape => 'assets/photo/landscape.json',
        PhotoAlbum.racing => 'assets/photo/racing.json',
        PhotoAlbum.alonso => 'assets/photo/alonso.json',
      };

  /// The photographs this album may show.
  List<AlbumPhoto> get pool => switch (this) {
        PhotoAlbum.landscape => landscapePool,
        PhotoAlbum.racing => racingPool,
        PhotoAlbum.alonso => [...alonsoCarPool, ...alonsoSubjectPool],
      };

  /// The half of the Alonso album where the car is the subject and he is in it.
  List<AlbumPhoto> get poolCar => switch (this) {
        PhotoAlbum.alonso => alonsoCarPool,
        _ => const [],
      };

  /// The half of the Alonso album where he is the subject.
  List<AlbumPhoto> get poolSubject => switch (this) {
        PhotoAlbum.alonso => alonsoSubjectPool,
        _ => const [],
      };

  /// May this album pick up new photographs from Commons at runtime?
  ///
  /// Only Landscape. The discovery categories are nature categories, and
  /// nothing in them is guaranteed to be a racing car.
  bool get usesDiscovery => this == PhotoAlbum.landscape;

  /// Restore an album from the stored setting.
  static PhotoAlbum fromName(String? name) => switch (name) {
        'racing' => PhotoAlbum.racing,
        'alonso' => PhotoAlbum.alonso,
        _ => PhotoAlbum.landscape,
      };

  /// The value stored in the settings file.
  String get storageName => name;

  // ── Landscape ─────────────────────────────────────────────────────────────

  static const List<AlbumPhoto> landscapePool = [
    AlbumPhoto(
      'Jokulsarlon lake, Iceland.jpg',
      'Kenny Muir',
    ),
    AlbumPhoto(
      'Lake Kinney mit Mount Whitehorn.jpg',
      'Florian Fuchs',
    ),
    AlbumPhoto(
      'Zagedan Lakes, Mountain cirque, Caucasus Mountains.jpg',
      'Vyacheslav Argenberg',
    ),
    AlbumPhoto(
      'Early morning light at the top of Poon Hill2.jpg',
      'Ali Sabbagh',
    ),
    AlbumPhoto(
      'Himalaya sunrise.jpg',
      'Ali Sabbagh',
    ),
    AlbumPhoto(
      'Khodz River Valley in fog, Adygea, Верховья реки Ходзь в тумане и облаках, Адыгея.jpg',
      'Vyacheslav Argenberg',
    ),
    AlbumPhoto(
      'Wisła pod Ochodzą w województwie małopolskim, 20231119 0706 2690.jpg',
      'Elaine Li',
    ),
    AlbumPhoto(
      'Asbestnaya Mount, Adygea, Гора Асбестная, виды с вершины, Адыгея, Западный Кавказ.jpg',
      'Vyacheslav Argenberg',
    ),
    AlbumPhoto(
      'Ella, Sri Lanka, Mountains in clouds, Panorama.jpg',
      'Vyacheslav Argenberg',
    ),
    AlbumPhoto(
      'River Running through a Rolling Hills Landscape by Edmund John Nieman .jpg',
      'Edmund John Nieman (1843-1910)',
    ),
    AlbumPhoto(
      'Rolling hills and lagoon scenics.jpg',
      'West Robin L, U.S. Fish and Wildlife Service',
    ),
  ];

  // ── Racing cars ───────────────────────────────────────────────────────────

  /// Formula One, Le Mans / WEC and rally machinery.
  ///
  /// Every entry was checked against the live Commons API: the file exists,
  /// the licence is public domain / CC0 / CC-BY, and a thumbnail can be
  /// fetched. Share-alike is absent on purpose — a launcher cannot honour it.
  static const List<AlbumPhoto> racingPool = [
    // Formula One
    AlbumPhoto(
      'Renault R25 2005 United States GP (19887965).jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      '2005-03-04 Motorshow Geneva 063.JPG',
      'Norbert Aepli',
    ),
    AlbumPhoto(
      '2005 F1 Champion (86733413).jpg',
      'Global Reactions',
    ),
    AlbumPhoto(
      'Renault R25 Display Car.JPG',
      'RB30DE',
    ),
    AlbumPhoto(
      'First corner 2005 Turkish Grand Prix.jpg',
      'Postmortem',
    ),
    AlbumPhoto(
      'GPTurkey05 start.jpg',
      'Postmortem',
    ),
    AlbumPhoto(
      'Lineup of Team Renault F1 Cars Old & New Goodwood 2011 (6005960130).jpg',
      'Louis Rix',
    ),
    AlbumPhoto(
      "1990's Classic Renault Team F1 Car Camel Sponsor (6005416583).jpg",
      'Louis Rix',
    ),
    AlbumPhoto(
      'Renault R25 V6 Turbo Baccara (1994) (55083089764).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Renault R25 V6 Turbo Baccara (1994) (55082827226).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Alpine Renault (8413756575).jpg',
      'Pedro Ribeiro Simões',
    ),

    // Le Mans and WEC
    AlbumPhoto(
      'Porsche 919 Hybrid (2016) (55082977438).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Porsche 919 Hybrid (2016) (55083142340).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Porsche 919 Hybrid (35916264611).jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      'Porsche 919 Hybrid (25152230266).jpg',
      'oaktree_brian_1976',
    ),
    AlbumPhoto(
      'Porsche 919 Hybrid, EMS 2014, IMG 0420-klein (22088826786).jpg',
      'Dennis Boberg',
    ),
    AlbumPhoto(
      '2014 Porsche 919 Hybrid Race Car (73530203).jpeg',
      'Doug Fawley',
    ),
    AlbumPhoto(
      'No. 2 Porsche 919 Hybrid - 2017 24 Hours of Le Mans.jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      'Audi-R18-TDI-2011.JPG',
      'Tom Schwede',
    ),
    AlbumPhoto(
      'Audi R18 TDI - Winning Car - Le Mans 24 Hours 2011 (6192211130).jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      "Audi Sport Team Joest's Audi R18 TDI (5847866203).jpg",
      'David Merrett',
    ),
    AlbumPhoto(
      'No. 8 Audi R18 (2016) - Lucas di Grassi, Loic Duval, Oliver Jarvis - 2016 24 Hours of Le Mans (1).jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      'Le Mans 2014 - LMP1 Hybrid - -1 Joest Audi R18 e-tron Quattro - Lucas di Grassi Marc Gene Tom Kristensen (14435272122).jpg',
      'Mark Seymour',
    ),
    AlbumPhoto(
      'Le Mans Audi (22908833).jpeg',
      'Outex Photo',
    ),
    AlbumPhoto(
      "2018 Toyota Gazoo Racing's Toyota TS050 Hydrid (49379920151).jpg",
      'David Merrett',
    ),
    AlbumPhoto(
      "Toyota Gazoo Racing's Toyota TS050 Hybrid (35879547962).jpg",
      'David Merrett',
    ),
    AlbumPhoto(
      "Toyota Gazoo Racing's Toyota TS050 Hybrid No. 8.jpg",
      'David Merrett',
    ),
    AlbumPhoto(
      '2011 Peugeot 908 (48452630792).jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      '2011 Peugeot 908 (48452480041).jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      '2011 Peugeot 908 Driven to 3rd overall by Stéphane Sarrazin, Frank Montagny and Nicolas Minassian at Le Mans 2011 (48452467216).jpg',
      'David Merrett',
    ),
    AlbumPhoto(
      '2011 Peugeot 908 Donington Park 2023 01.jpg',
      'Julian Herzog',
    ),
    AlbumPhoto(
      '2023 24 Hours of Le Mans (53270863207).jpg',
      'mickael LE ROUZIC',
    ),
    AlbumPhoto(
      '2023 24 Hours of Le Mans (53271753076).jpg',
      'mickael LE ROUZIC',
    ),

    // Rally
    AlbumPhoto(
      '2005 Citroen Xsara WRC rally car (5963343792).jpg',
      'sv1ambo',
    ),
    AlbumPhoto(
      '2005 Citroen Xsara WRC rally car (5963347930).jpg',
      'sv1ambo',
    ),
    AlbumPhoto(
      '2005 Citroen Xsara WRC.JPG',
      'Przemysław JahrA',
    ),
    AlbumPhoto(
      'Xsara WRC.JPG',
      '306maxi',
    ),
    AlbumPhoto(
      'Citroen Xsara VTS Sport.jpg',
      'Guillaume Vachey',
    ),
    AlbumPhoto(
      'Citroen Xsara VTS Sport (29029802398).jpg',
      'Guillaume Vachey',
    ),
    AlbumPhoto(
      'BMW M3 Rally Coupé (E30, 1988) (53767149093).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'BMW M3 Rally Coupé (E30, 1988) (53766049107).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Lancia Stratos HF Group 4 Rally (1978) (52867387191).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Lancia Stratos HF Group 4 Rally (1978) (52867829933).jpg',
      'Charles',
    ),
    AlbumPhoto(
      'Lancia Stratos HF Rally.jpg',
      '35mmMan',
    ),
    AlbumPhoto(
      'Lancia Stratos (49817653007).jpg',
      'Pedro Ribeiro Simões',
    ),
    AlbumPhoto(
      'Ford RS200 (28805594035).jpg',
      'Steven Straiton',
    ),
    AlbumPhoto(
      '1986 Ford RS200.jpg',
      'Dave Hamster',
    ),
    AlbumPhoto(
      'Ford Fiesta RS WRC 2011 001.jpg',
      'Ford Motor Company',
    ),
    AlbumPhoto(
      'Hyundai Accent WRC Goodwood FOS 2018.jpg',
      'BWard 1997',
    ),
    AlbumPhoto(
      'Peugeot 206 WRC - Side view.jpg',
      'Haseo',
    ),
    AlbumPhoto(
      'Hyundai i20 WRC 2013 Car Launch 001.jpg',
      'Hyundai Motorsport',
    ),
  ];

  // ── Fernando Alonso ───────────────────────────────────────────────────────

  /// In the car. Renault, McLaren, Ferrari, Toyota and Aston Martin.
  static const List<AlbumPhoto> alonsoCarPool = [
    // Renault
    AlbumPhoto(
      'Fernando Alonso 2005 China.jpg',
      'Tinou Bao',
    ),
    AlbumPhoto(
      'Renault R28 Fernando Alonso (17887964188).jpg',
      'Rob Oo',
    ),
    AlbumPhoto(
      'Renault Pit Box, Imola 2005.jpg',
      'Alexandre López',
    ),
    AlbumPhoto(
      'McLarens 2005 San Marino.jpg',
      'Alexandre López',
    ),
    AlbumPhoto(
      'Fernando Alonso 2006 Indianapolis.jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Fernando Alonso 2006 Indianapolis 2.jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Fernando Alonso 2006 United States GP (178147950).jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Fernando Alonso US GP 2006.jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Renault duo 2006 United States GP (183782255).jpg',
      'Ryosuke Yagi',
    ),
    // McLaren
    AlbumPhoto(
      'F1 - Mclaren Honda - Fernando Alonso (28298388680).jpg',
      'Jen_ross83',
    ),
    AlbumPhoto(
      'Fernando Alonso - McLaren (33108833555).jpg',
      'Jake Archibald',
    ),
    AlbumPhoto(
      'Fernando Alonso, McLaren-Honda MP4-31, 2016 British Grand Prix, Silverstone, 9th July (28237466492).jpg',
      'Interceptor73',
    ),
    AlbumPhoto(
      'Fernando Alonso 2016 British Grand Prix.jpg',
      'Ben Sutherland',
    ),
    // Ferrari
    AlbumPhoto(
      'Ferrari F1 - Fernando Alonso (5178411980).jpg',
      'Jitesh Jagadish',
    ),
    AlbumPhoto(
      '2012 Italian GP - Alonso on pit.jpg',
      'Francesco Crippa',
    ),
    AlbumPhoto(
      '2012 Japan GP - Alonso car.jpg',
      'Norimasa Hayashida',
    ),
    // The rest of the career
    AlbumPhoto(
      'Fernando Alonso on three wheels during 2009 Hungarian Grand Prix.jpg',
      'Kleczu',
    ),
    AlbumPhoto(
      'FIA F1 Imola 2025 No. 14 Alonso.jpg',
      'Jen_ross83',
    ),
  ];

  /// Him as the subject: the podiums, the press conferences, the champagne.
  static const List<AlbumPhoto> alonsoSubjectPool = [
    AlbumPhoto(
      '2012 Italian GP - Champagne.jpg',
      'Francesco Crippa',
    ),
    AlbumPhoto(
      '2012 Italian GP - drivers press conference.jpg',
      'Francesco Crippa',
    ),
    AlbumPhoto(
      '2012 Italian GP - Alonso cameraman 3.jpg',
      'Francesco Crippa',
    ),
    AlbumPhoto(
      'Alonso Barca 2012.jpg',
      'los_bandito_anthony',
    ),
    AlbumPhoto(
      'Fernando Alonso - Inggris 2012.jpg',
      'Supermac1961',
    ),
    AlbumPhoto(
      'Ferrari Alonso and McLaren Hamilton Barcelona 2012.jpg',
      'Rich Jones',
    ),
    AlbumPhoto(
      'Fernando Alonso and Jacques Villeneuve 2006 Indianapolis.jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Giancarlo Fisichella and Fernando Alonso 2006 Indianapolis.jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Giancarlo Fisichella and Fernando Alonso 2006 Indianapolis 3.jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      'Michael Schumacher and Fernando Alonso 2006 United States GP (179685135).jpg',
      'Ryosuke Yagi',
    ),
    AlbumPhoto(
      '2019 Indianapolis 500, Fernando Alonso - 01.jpg',
      'Zach Catanzareti Photo',
    ),
    AlbumPhoto(
      '2019 Indianapolis 500, Fernando Alonso - 02.jpg',
      'Zach Catanzareti Photo',
    ),
    AlbumPhoto(
      'Fernando Alonso (35461870753).jpg',
      'Jake Archibald',
    ),
  ];
}
