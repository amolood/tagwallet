package com.example.tagwallet

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

/**
 * Minimal HCE service. When a reader selects our AID, we reply with the response
 * configured for the currently-active emulated tag.
 *
 * Scope and honest limits:
 *  - This emulates an ISO-DEP (ISO 14443-4 / Type-4) APDU card only.
 *  - It CANNOT present a chosen UID, cannot emulate MIFARE Classic sectors,
 *    and cannot access the secure element. Readers that authenticate on those
 *    will not be opened by this.
 *  - Use only with systems you are authorized to access.
 *
 * The "active tag" is selected from Flutter and stored in SharedPreferences as:
 *   active_aid       -> hex string of the AID the reader will SELECT
 *   active_response  -> hex string returned after a successful SELECT
 */
class TagHostApduService : HostApduService() {

    companion object {
        private const val TAG = "TagHCE"
        const val PREFS = "tagwallet_hce"
        const val KEY_AID = "active_aid"
        const val KEY_RESPONSE = "active_response"

        // ISO 7816-4 status words
        private val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())
        private val SW_INS_NOT_SUPPORTED = byteArrayOf(0x6D.toByte(), 0x00)

        private const val INS_SELECT = 0xA4
        private const val CLA_ISO = 0x00
    }

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        if (commandApdu == null || commandApdu.size < 4) return SW_INS_NOT_SUPPORTED
        Log.d(TAG, "APDU in: ${commandApdu.toHex()}")

        val cla = commandApdu[0].toInt() and 0xFF
        val ins = commandApdu[1].toInt() and 0xFF

        // We handle SELECT (by AID/by name). Everything else: return the stored response
        // if present, else "not supported".
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val responseHex = prefs.getString(KEY_RESPONSE, null)

        if (cla == CLA_ISO && ins == INS_SELECT) {
            val activeAid = prefs.getString(KEY_AID, null)
            val selectedAid = parseSelectAid(commandApdu)
            return if (activeAid != null && selectedAid != null &&
                       activeAid.equals(selectedAid, ignoreCase = true)) {
                val payload = responseHex?.hexToBytes() ?: ByteArray(0)
                payload + SW_OK
            } else {
                SW_NOT_FOUND
            }
        }

        // Non-SELECT command: replay stored response if configured.
        return if (responseHex != null) responseHex.hexToBytes() + SW_OK else SW_INS_NOT_SUPPORTED
    }

    override fun onDeactivated(reason: Int) {
        Log.d(TAG, "Deactivated: $reason")
    }

    /** Extract the AID bytes from a SELECT-by-DF-name APDU (00 A4 04 00 Lc AID...). */
    private fun parseSelectAid(apdu: ByteArray): String? {
        if (apdu.size < 6) return null
        val lc = apdu[4].toInt() and 0xFF
        if (lc <= 0 || apdu.size < 5 + lc) return null
        return apdu.copyOfRange(5, 5 + lc).toHex()
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02X".format(it) }

    private fun String.hexToBytes(): ByteArray {
        val clean = replace(" ", "")
        return ByteArray(clean.length / 2) {
            ((Character.digit(clean[it * 2], 16) shl 4) +
             Character.digit(clean[it * 2 + 1], 16)).toByte()
        }
    }
}
