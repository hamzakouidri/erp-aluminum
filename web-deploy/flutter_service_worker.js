'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "a1abbc7289830f1955850f7e22129344",
"assets/AssetManifest.bin.json": "d3b2cc7294f477c63c451fafcbb878d4",
"assets/assets/fonts/Amiri-Bold.ttf": "9d358a17fee722a979ee2f314e342937",
"assets/assets/fonts/Amiri-Regular.ttf": "ec11e84334894cf790512622f57e3190",
"assets/assets/fonts/Arial-Regular.ttf": "80ba139eae9f6344f167e76b7a0474c8",
"assets/assets/fonts/Cairo-Bold.ttf": "0e355a997fd3fdc3a2a5d13ba68a6fd0",
"assets/assets/fonts/Cairo-Regular.ttf": "0e355a997fd3fdc3a2a5d13ba68a6fd0",
"assets/assets/fonts/Cairo.ttf": "0e355a997fd3fdc3a2a5d13ba68a6fd0",
"assets/assets/images/app_icon.png": "c1fb6972030585481bdf2cc4512c2802",
"assets/assets/images/caisson%2520tunnel.jpg": "35f290f8d81450d2b7b009c30627f1fb",
"assets/assets/images/EX451513.svg": "0c26754dd69a26a00a62bbe2d0e26f31",
"assets/assets/images/warshati_logo_glowing.png": "0280de09f2c6daff864f194754075ba8",
"assets/assets/images/water_ripples.mp4": "f21c205d3e9b8b3630b6e02fe720e0d3",
"assets/assets/images/water_ripples.png": "d2096ecd4f694871bfc445469944ae2d",
"assets/assets/images/wood_texture.png": "01c30875bc9f1731699ce8cbc70d8b91",
"assets/assets/images/wood_texture_antique.png": "e5d7c9698a742011dcb610b06cd02dd5",
"assets/assets/images/wood_texture_d0.png": "50bcd07b0c76a6fe1e3590e28fed2075",
"assets/assets/images/wood_texture_dark.png": "b295c51772965dd009350098c37d8026",
"assets/assets/images/wood_texture_grey.png": "5465a0d72697f11841f470f56d00daed",
"assets/assets/sections/%25D8%25A3%25D9%2588%25D9%2586%25D8%25AA%25D8%25B1%25D9%2588%25D9%2585%25D8%25A7%25D8%25AA%25D9%258A%25D9%2583.png": "25e6b048888822f4641acc1b371a41c0",
"assets/assets/sections/%25D8%25A8%25D8%25B1%25D8%25A7%25D8%25BA%25D9%258A.png": "88e24baf497d5b36ad7fc8b3b876cd98",
"assets/assets/sections/%25D8%25B9%25D8%25AC%25D9%2584%25D8%25A7%25D8%25AA_%25D8%25A7%25D9%2584%25D9%2585%25D9%2586%25D8%25B2%25D9%2584%25D9%2582.png": "e82cbcb201946bd122ae9b66443c4504",
"assets/assets/sections/103.png": "c0fb208d80d1f8d36df880dbce3c1980",
"assets/assets/sections/104.png": "cab66c2adcdf3847bf01ada8ba1bb013",
"assets/assets/sections/105.png": "bd7507d7bedb1d349e7aba4d062a6412",
"assets/assets/sections/106.png": "34db804b1f7e95c76f883d81984158ed",
"assets/assets/sections/107.png": "024c3606f93099e4efd038f1bf6c9074",
"assets/assets/sections/108.png": "3fa2abdb50188e1aad4d917aec287497",
"assets/assets/sections/116.png": "e5142d0bd7b54d73c2f575002fc396a2",
"assets/assets/sections/11690.png": "d5551d91f515a43e6cc5ddda1aab8c2b",
"assets/assets/sections/116b.png": "d5551d91f515a43e6cc5ddda1aab8c2b",
"assets/assets/sections/127.png": "c2b2dd40dbe3a4c8ab1a0f5c1685fa99",
"assets/assets/sections/140.png": "c6a6b3dff2dcd920df5948c4f90565b0",
"assets/assets/sections/222.png": "25970cfc1370e2e4391032e82e4b3c41",
"assets/assets/sections/225.png": "e0f1849d81dc032dce930706cb8560ed",
"assets/assets/sections/40102.png": "be5f1a7e434362d2397fa17d48012d8f",
"assets/assets/sections/40104.png": "f5af1681b8a8b3b69c275f77cdfa7eda",
"assets/assets/sections/40111.png": "250533a3ad1072ff303f9a2b5313b3d7",
"assets/assets/sections/40112.png": "21511debd4cb509285a98cef706fad62",
"assets/assets/sections/40121.png": "b9e696682bfd48941bd85eff4e5446f9",
"assets/assets/sections/40139.png": "8beb9270e32e3745d1fa3f5f09db22fa",
"assets/assets/sections/40149.png": "2bf2e48971b500aa790aa457b5744ed2",
"assets/assets/sections/40151.png": "db4a6f48c54be22ddf4c455cccc327ce",
"assets/assets/sections/40154.png": "59b1d0089948e1cc6eeade045467b848",
"assets/assets/sections/40401.png": "376937651d2c59fd49e2e9745fc10c6d",
"assets/assets/sections/40402.png": "5064130b75045392a565f2c0689c1845",
"assets/assets/sections/40403.png": "ebecdc848944fc3664c0a8cec0716d41",
"assets/assets/sections/40407.png": "afe9be9b90cb8828f76e2b72a7379f41",
"assets/assets/sections/40408.png": "6e61ce88f6d63d84607c7b2b8b90e650",
"assets/assets/sections/511.png": "3b82ccac61bb9572843a73156a7d43f0",
"assets/assets/sections/511c.png": "3b82ccac61bb9572843a73156a7d43f0",
"assets/assets/sections/514.png": "98a565d7b2eada270a726802c78ea7ea",
"assets/assets/sections/514c.png": "98a565d7b2eada270a726802c78ea7ea",
"assets/assets/sections/52035.png": "ca2023a14777e470c68b2b0343f8bdb5",
"assets/assets/sections/52036.png": "3c78972c0b89f89427636e09bf005583",
"assets/assets/sections/67101.svg": "9b12c83887e3fcf6dd298d31fece1f2d",
"assets/assets/sections/67102.svg": "9c31251dbbbc701b4e1184c9bf477b0f",
"assets/assets/sections/67103.svg": "5a85e7bc8d2388054a00612815798827",
"assets/assets/sections/67104.svg": "919ad6f30b7b59ba4c90722cf7bcdf72",
"assets/assets/sections/67105.svg": "a23d2f02318c9da17c6a84edbf35a7af",
"assets/assets/sections/67106.svg": "887a9c77b425f23c457d1925dc12e4ca",
"assets/assets/sections/67107.svg": "bef90d71ac97dbe19d14ddf4f8832adf",
"assets/assets/sections/67108.svg": "eef44b6caeb3d80c911aebbea5dbc438",
"assets/assets/sections/67110.svg": "c892946473398c30005df9104fbbe50a",
"assets/assets/sections/67111.svg": "0b2c54537f7c95f10b1e67b2c7202ca6",
"assets/assets/sections/67112.svg": "e27e63586954aa652f39fc9af59075c4",
"assets/assets/sections/67113.svg": "5d1885ab657fdd0081484d13c4edc606",
"assets/assets/sections/67114.svg": "8fa8f4a2cf04fd7837fb3aa809574f2f",
"assets/assets/sections/67115.svg": "269d18495e313739aee570f1f728e212",
"assets/assets/sections/76109.svg": "07086e9ac976cb4ffae665d393f0d595",
"assets/assets/sections/80116.svg": "1b829f78be2ea4d63cc54787e5f73414",
"assets/assets/sections/80124.svg": "47b8c8506969f9feef0aa6dbc9103979",
"assets/assets/sections/B108.png": "a3fe5811458d0f52dc51e8f5f67be417",
"assets/assets/sections/Capture%2520d'%25C3%25A9cran%25202026-07-13%2520150706.png": "14c89e95969b40793e8164aade6853f3",
"assets/assets/sections/Capture%2520d'%25C3%25A9cran%25202026-07-13%2520150710.png": "6d8405b35e64e19579ee937fbc232065",
"assets/assets/sections/Clam%252067000.png": "b1693c7e96f68bd18b1891385a72021e",
"assets/assets/sections/coulisse%2520pvc.png": "4258e3d67e421e4b2174878991f0961a",
"assets/assets/sections/cremone.png": "ffcf99a4dd8fe74e0d64c099aee1f22b",
"assets/assets/sections/entrematique.png": "25e6b048888822f4641acc1b371a41c0",
"assets/assets/sections/EX451513.svg": "0c26754dd69a26a00a62bbe2d0e26f31",
"assets/assets/sections/gache%2520colissante%2520tpr.png": "04b4ea684ce3f6d9d310074d33f3019f",
"assets/assets/sections/gache_colissante_tpr.png": "04b4ea684ce3f6d9d310074d33f3019f",
"assets/assets/sections/gache_coulissant_tpr.png": "04b4ea684ce3f6d9d310074d33f3019f",
"assets/assets/sections/intramatique%2520avec%2520cle.png": "18021dc17c4c4ece400c9f395312fdb8",
"assets/assets/sections/intramatique.png": "25e6b048888822f4641acc1b371a41c0",
"assets/assets/sections/joint%2520Bross.png": "e1f8c6632eb6969fe3136a8247f2a40d",
"assets/assets/sections/joint_bross.png": "e1f8c6632eb6969fe3136a8247f2a40d",
"assets/assets/sections/joint_brosse.png": "e1f8c6632eb6969fe3136a8247f2a40d",
"assets/assets/sections/joint_brosse_sash.png": "e1f8c6632eb6969fe3136a8247f2a40d",
"assets/assets/sections/joint_brosse_shutter.png": "e1f8c6632eb6969fe3136a8247f2a40d",
"assets/assets/sections/kit%252067000.png": "724f61de1587a61a7e02cf1dd06b2084",
"assets/assets/sections/kit%252067107.png": "0c99940df16696b2b14a3fbff1a183fb",
"assets/assets/sections/kit%252067108.png": "59ececb40226de9dfa8789700a1db31c",
"assets/assets/sections/logteau.png": "8cf9654df46481e848044477b16d1fe5",
"assets/assets/sections/N242.png": "0a6597b97348d3902fbc339c44e0de7d",
"assets/assets/sections/N243.png": "b8914cb299826e8740cc7d25da0fbb84",
"assets/assets/sections/roulette.png": "e82cbcb201946bd122ae9b66443c4504",
"assets/assets/sections/roulettes.png": "e82cbcb201946bd122ae9b66443c4504",
"assets/assets/sections/roulette_double.png": "e82cbcb201946bd122ae9b66443c4504",
"assets/assets/sections/serrure.png": "8333e04fda08cf9a273287b759b015ae",
"assets/assets/sections/vis.png": "88e24baf497d5b36ad7fc8b3b876cd98",
"assets/assets/sections/visse.png": "88e24baf497d5b36ad7fc8b3b876cd98",
"assets/FontManifest.json": "10532b924596f7aa0c396b2ee96ef4dc",
"assets/fonts/MaterialIcons-Regular.otf": "010a84b7c5b5016c4df345dc5bcfa80f",
"assets/Icon/a.png": "9890cf0b14631970f8ac4718cfd87757",
"assets/Icon/caisson_tunnel.jpg": "17a757ced85f87e44b8e653990668030",
"assets/Icon/f+v.jpg": "2f174fca9225829d5f220f1cb30fb679",
"assets/Icon/fdo.png": "db8ffa4fe24b0c18e44dee0ee31b0c0d",
"assets/Icon/ff.jpg": "47020219d4a96c1cbd8e14bc2fce1c92",
"assets/Icon/frame.png": "244817b902b774e9aaf65aaff91cebd4",
"assets/Icon/french.png": "41e5a34d683900a4c01f108092e8b85f",
"assets/Icon/media.webp": "21982ac86ccc20daa09b07f2835a3f88",
"assets/Icon/p.png": "bd494ade6a736c3b6c42900beab53856",
"assets/Icon/port.png": "f9b71206a0a7898efd4171e578370bc3",
"assets/Icon/roling.png": "c415522b4e7501ad577e24d99609759e",
"assets/Icon/sli.png": "6c2072762b373c57cd26484af67879af",
"assets/Icon/verre.png": "a35ba57208bb5bf2bdf5354011182407",
"assets/NOTICES": "1a1d049a5d45fba1145e23f39ac61612",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/flutter_map/lib/assets/flutter_map_logo.png": "208d63cc917af9713fc9572bd5c09362",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/web/sqlite3.wasm": "fa7637a49a0e434f2a98f9981856d118",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"flutter_bootstrap.js": "ebbd65e021ae49739132c74a9c8d5d30",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "752c99799fb0597086d1c2f009854e13",
"/": "752c99799fb0597086d1c2f009854e13",
"main.dart.js": "8a5243ae4ffbb813668bc29d33174678",
"manifest.json": "6d9001703a66f3ae2df578885533ced0",
"sqlite3.wasm": "fa7637a49a0e434f2a98f9981856d118",
"version.json": "bd21830f24eaaec69d272b2af7d0b030"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
