# GlassSearch (iOS 15, SpringBoard)

Isi: pill "Search" liquid glass di atas dock -> tap -> layar blur, search bar nempel
di atas keyboard (seperti iOS 26), hasil app muncul di atas bar, "Search Web" di baris terakhir.

## Build
1. Install Theos + SDK iOS 15.
2. `cd GlassSearch && make package`
3. Install .deb hasilnya. Matikan tweak SearchDots dulu (bentrok posisi pill).
   Kalau jailbreak rootful, hapus baris THEOS_PACKAGE_SCHEME di Makefile dan ganti Architecture di `control` jadi iphoneos-arm.

## Swipe-down (ganti Spotlight bawaan)
Nama kelas/metode Spotlight iOS 15 harus dicek di perangkatmu:
1. Buat file kosong `/var/mobile/GlassSearch_dump`, lalu respring.
2. Buka `/var/mobile/GlassSearch_classes.txt` -> kirim isinya ke saya.
3. Dari situ kita isi `/var/mobile/GlassSearch_hooks.txt` (satu baris per hook: `NamaKelas namaSelector`),
   tanpa compile ulang. Selector harus return void atau BOOL.

## Build lewat GitHub Actions
Taruh isi folder ini (Tweak.x, Makefile, control, GlassSearch.plist, folder .github) di root repo,
push ke branch main. Hasil .deb ada di tab Actions -> run terbaru -> Artifacts -> GlassSearch-deb.
