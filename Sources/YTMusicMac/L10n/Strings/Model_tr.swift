let modelTR: [String: String] = [
    // Türkçe'de sayıdan sonra çoğul eki yok — .one ve .other aynı.
    "vm.count.songs.one": "%d şarkı",
    "vm.count.songs.other": "%d şarkı",

    // Arama sekmeleri
    "vm.search.tab.playlists": "Çalma listeleri",
    "vm.search.tab.songs": "Şarkılar",
    "vm.search.tab.artists": "Sanatçılar",
    "vm.search.tab.albums": "Albümler",

    // Liste gizliliği
    "vm.privacy.public": "Herkese açık",
    "vm.privacy.unlisted": "Liste dışı (bağlantısı olan)",
    "vm.privacy.private": "Özel",

    // Hata bandı
    "vm.banner.offline": "İnternet bağlantısı yok.",
    "vm.banner.signedOut": "YT Music oturumun düşmüş. Kitaplığın ve beğenilerin yüklenemiyor.",
    "vm.banner.signIn": "Giriş yap",

    // Sayfa içi yükleme hataları
    "vm.error.entityFailed": "%@ yüklenemedi.",
    "vm.error.artistFailed": "Sanatçı yüklenemedi.",
    "vm.error.libraryNeedsSignIn": "Kitaplığını görmek için YT Music'e giriş yap.",
    "vm.error.noPlaylists": "Henüz çalma listen yok.",
    "vm.error.libraryFailed": "Kitaplık yüklenemedi.",
    "vm.error.categoryEmpty": "Bu kategoride çalma listesi yok.",
    "vm.error.categoryFailed": "Bu kategori yüklenemedi.",
    "vm.error.playlistEmpty": "Bu liste boş.",
    "vm.error.tracksFailed": "Şarkılar yüklenemedi.",
    "vm.error.homeFailed": "Ana sayfa yüklenemedi.",
    "vm.error.historyNeedsSignIn": "Geçmişi görmek için YT Music'e giriş yap.",
    "vm.error.historyEmpty": "Geçmiş boş.",
    "vm.error.historyFailed": "Geçmiş yüklenemedi.",
    "vm.error.exploreFailed": "Keşfet yüklenemedi.",
    "vm.error.searchEmpty": "Sonuç yok.",
    "vm.error.searchFailed": "Arama başarısız",
    "vm.error.noTrackPlaying": "Çalan şarkı yok",

    // Şarkı sözleri
    "vm.lyrics.unavailable": "Bu şarkı için sözler yok",
    "vm.lyrics.notFound": "Sözler bulunamadı",
    "vm.lyrics.failed": "Sözler yüklenemedi",

    // Benzer parça listesi (Last.fm)
    "vm.similar.defaultTitle": "%@ — Benzerler",
    "vm.similar.description": "%@ • %@ — Last.fm benzerleri",

    // Bildirimler — listeler
    "vm.toast.orderReset": "Sıralama sıfırlandı",
    "vm.toast.playlistNameRequired": "Liste adı gerekli",
    "vm.toast.playlistCreated": "“%@” oluşturuldu",
    "vm.toast.playlistCreatedWithTracks": "“%@” oluşturuldu, %@ eklendi",
    "vm.toast.playlistCreateFailed": "Liste oluşturulamadı",
    "vm.toast.playlistCreateFailedHTTP": "Liste oluşturulamadı (HTTP %d)",
    "vm.toast.playlistNotEditable": "%@ düzenlenemiyor",
    "vm.toast.playlistSaved": "“%@” kitaplığa kaydedildi",
    "vm.toast.playlistRemoved": "“%@” kitaplıktan çıkarıldı",
    "vm.toast.renamed": "Yeniden adlandırıldı: %@",
    "vm.toast.renameFailed": "Adlandırılamadı",
    "vm.toast.renameFailedHTTP": "Adlandırılamadı (HTTP %d)",
    "vm.toast.deleted": "Silindi: %@",
    "vm.toast.deleteFailed": "Silinemedi",
    "vm.toast.deleteFailedHTTP": "Silinemedi (HTTP %d)",
    "vm.toast.reorderSaveFailed": "Sıralama kaydedilemedi",
    "vm.toast.emptyList": "Boş liste",

    // Bildirimler — albümler
    "vm.toast.albumNotSavable": "Bu albüm kaydedilemiyor",
    "vm.toast.albumSaved": "Albüm kitaplığa eklendi",
    "vm.toast.albumRemoved": "Albüm kitaplıktan çıkarıldı",

    // Bildirimler — sanatçılar
    "vm.toast.artistNotFound": "Sanatçı bulunamadı",
    "vm.toast.artistOpenFailed": "Sanatçı açılamadı",

    // Bildirimler — listedeki parçalar
    "vm.toast.tracksNotRemovable": "Bu parçalar listeden çıkarılamıyor",
    "vm.toast.removedFromPlaylist": "Listeden çıkarıldı",
    "vm.toast.tracksRemovedFromPlaylist": "%@ listeden çıkarıldı",
    "vm.toast.removeFailed": "Çıkarılamadı",
    "vm.toast.removeFailedHTTP": "Çıkarılamadı (HTTP %d)",
    "vm.toast.tracksAddedToPlaylist": "%@, “%@” listesine eklendi",
    "vm.toast.trackAddedToPlaylist": "“%@” → %@",
    "vm.toast.trackLikedMusic": "“%@” Beğenilen Müzikler'e eklendi",
    "vm.toast.addFailed": "Eklenemedi",
    "vm.toast.addFailedHTTP": "Eklenemedi (HTTP %d)",
    "vm.toast.saveFailed": "Kaydedilemedi",
    "vm.toast.saveFailedHTTP": "Kaydedilemedi (HTTP %d)",

    // Bildirimler — kuyruk
    "vm.toast.playNext": "Sıradaki: %@",
    "vm.toast.addedToQueue": "Kuyruğa eklendi: %@",
    "vm.toast.tracksQueued": "%@ kuyruğa eklendi",
    "vm.toast.queueAddFailed": "Kuyruğa eklenemedi",
    "vm.toast.queueCleared": "Kuyruk temizlendi",

    // Bildirimler — beğeniler
    "vm.toast.liked": "Beğenildi: %@",
    "vm.toast.likeFailed": "Beğenilemedi",
    "vm.toast.likeFailedHTTP": "Beğenilemedi (HTTP %d)",
    "vm.toast.disliked": "Beğenilmedi: %@",
    "vm.toast.signInToLike": "Beğenmek için YT Music'e giriş yap",
    "vm.toast.dislikeMarked": "Beğenilmedi olarak işaretlendi",
    "vm.toast.dislikeCleared": "İşaret kaldırıldı",
    "vm.toast.likeAdded": "Beğenilenlere eklendi",
    "vm.toast.likeRemoved": "Beğeni kaldırıldı",
    "vm.toast.likeAPIRejected": "Beğeni API'si reddetti (HTTP %d) — sayfadan denendi",
    "vm.toast.likeSendFailed": "Beğeni gönderilemedi — sayfadan denendi",
    "vm.toast.tracksLiked": "%@ Beğenilenlere eklendi",

    // Bildirimler — benzer liste
    "vm.toast.signInForPlaylist": "Liste için YT Music'e giriş yap",
    "vm.toast.lastfmKeyMissing": "Last.fm anahtarı ayarlı değil",
    "vm.toast.similarNotPossible": "Bu parça için liste yapılamıyor",
    "vm.toast.noSimilarTracks": "Benzer parça bulunamadı",
    "vm.toast.noMatchedTracks": "Eşleşen parça bulunamadı",

    // Bildirimler — diğer
    "vm.toast.radioStarting": "Radyo başlatılıyor",
    "vm.toast.linkCopied": "Bağlantı kopyalandı",
    "vm.toast.actionFailed": "İşlem başarısız",
    "vm.toast.actionFailedHTTP": "İşlem başarısız (HTTP %d)",
    "vm.error.radioFailed": "Radyo yüklenemedi.",
    "vm.radio.discovery.title": "Günlük keşif",
    "vm.radio.discovery.subtitle": "Kitaplığından beslenen altı radyo — her gün yenisi",
    "vm.radio.artists.title": "Sanatçı radyoları",
    "vm.radio.artists.subtitle": "En çok dinlediğin sanatçıların etrafında kurulu",
    "vm.radio.artistStation": "%@ radyosu",
    "vm.radio.forYou.title": "Favorilerin radyoda",
    "vm.radio.forYou.subtitle": "Sevdiğin bir şarkıdan başla, devamı gelsin",
    "vm.radio.ytMixes.title": "YouTube karışımları",
    "vm.radio.ytMixes.subtitle": "YouTube'un senin için hazırladığı karışımlar",
    "vm.home.weeklyMix.title": "Haftalık karışımın",
    "vm.home.weeklyMix.subtitle": "Her hafta kitaplığından yeni bir seçki",
    "vm.home.yearAgo.title": "Bir yıl önce bugün",
    "vm.home.yearAgo.subtitle": "Geçen yıl bugün neler dinliyordun",
    "vm.home.sixMonths.title": "Altı ay önce",
    "vm.home.sixMonths.subtitle": "Yarım yıl önce tekrar tekrar çaldığın ay",
    "vm.search.recentlyPlayed.title": "Son çaldıkların",
    "vm.search.recentlyPlayed.subtitle": "Kaldığın yerden devam et",
    "vm.home.forgotten.title": "Unuttuğun favoriler",
    "vm.home.forgotten.subtitle": "Bir zamanlar çok çaldın, sonra bıraktın",
    "vm.toast.mixQueued.one": "%d parça çalınıyor",
    "vm.toast.mixQueued.other": "%d parça çalınıyor",
]
