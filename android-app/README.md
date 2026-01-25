# 📱 Onyx - Instagram sans distractions

Application Android et extension Chrome pour utiliser Instagram sans les Reels et autres distractions, avec support des notifications et appels.

## ✨ Fonctionnalités

### Filtres
- 🚫 **Masquer les Reels** - Cache tous les liens et contenus Reels
- 🔍 **Masquer Explorer** - Cache le lien vers la page Explorer  
- 📢 **Masquer les publicités** - Tente de cacher les posts sponsorisés
- 💬 **Messages préservés** - Les filtres sont désactivés dans les DMs

### Notifications & Appels (Android)
- 🔔 **Notifications interceptées** - Reçoit les notifications d'Instagram
- 📞 **Appels** - Support des appels vidéo/audio
- ⚙️ **Choix de l'app** - Ouvrir les appels dans Onyx ou Instagram

## 📱 Application Android

### Comment compiler l'APK

1. **Installer Android Studio** depuis [developer.android.com](https://developer.android.com/studio)
2. **Ouvrir le projet** : File → Open → Sélectionner le dossier `android-app`
3. **Attendre** que Gradle synchronise les dépendances
4. **Générer l'APK** : Build → Build Bundle(s) / APK(s) → Build APK(s)
5. L'APK sera dans `app/build/outputs/apk/debug/`

### Configuration des notifications

1. Installer l'APK sur votre téléphone
2. Ouvrir Onyx
3. Aller dans **Paramètres** → **Activer les notifications**
4. Autoriser Onyx à lire les notifications
5. ✅ Vous recevrez désormais les notifications Instagram via Onyx

### ⚠️ Prérequis pour les notifications
L'app Instagram officielle doit rester installée (elle reçoit les notifications en arrière-plan), mais vous n'avez pas besoin de l'ouvrir.

## 🌐 Extension Chrome

L'extension se trouve à la racine du dossier. Pour l'installer :

1. Ouvrir Chrome → `chrome://extensions/`
2. Activer le **Mode développeur**
3. Cliquer sur **Charger l'extension non empaquetée**
4. Sélectionner le dossier `IcareLite` (racine)

## 📂 Structure du projet

```
IcareLite/
├── manifest.json          # Extension Chrome
├── content.js             # Script Chrome
├── options.html           # Options Chrome
├── options.js
└── android-app/           # Application Android
    ├── app/
    │   ├── src/main/
    │   │   ├── kotlin/com/onyx/app/
    │   │   │   ├── MainActivity.kt
    │   │   │   ├── SettingsActivity.kt
    │   │   │   └── InstagramNotificationListener.kt
    │   │   └── res/
    │   └── build.gradle
    └── settings.gradle
```

## ⚠️ Avertissement

Application indépendante, non affiliée à Meta/Instagram.
