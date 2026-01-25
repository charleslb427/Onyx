package com.onyx.app

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationManagerCompat
import androidx.preference.Preference
import androidx.preference.PreferenceFragmentCompat
import com.onyx.app.databinding.ActivitySettingsBinding

class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = getString(R.string.settings_title)

        supportFragmentManager
            .beginTransaction()
            .replace(R.id.settings_container, SettingsFragment())
            .commit()
    }

    override fun onSupportNavigateUp(): Boolean {
        onBackPressed()
        return true
    }

    class SettingsFragment : PreferenceFragmentCompat() {
        override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
            setPreferencesFromResource(R.xml.preferences, rootKey)
            
            // Handle notification listener preference click
            findPreference<Preference>("notification_listener")?.setOnPreferenceClickListener {
                val enabledListeners = NotificationManagerCompat.getEnabledListenerPackages(requireContext())
                if (!enabledListeners.contains(requireContext().packageName)) {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                }
                true
            }
        }
        
        override fun onResume() {
            super.onResume()
            updateNotificationListenerStatus()
        }
        
        private fun updateNotificationListenerStatus() {
            val enabledListeners = NotificationManagerCompat.getEnabledListenerPackages(requireContext())
            val isEnabled = enabledListeners.contains(requireContext().packageName)
            
            findPreference<Preference>("notification_listener")?.summary = if (isEnabled) {
                "✅ Activé - Onyx reçoit les notifications Instagram"
            } else {
                "❌ Désactivé - Cliquez pour activer"
            }
        }
    }
}
