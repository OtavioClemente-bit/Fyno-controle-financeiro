
package com.example.controle_financeiro.notifications

import android.content.Context
import org.json.JSONObject
import java.io.File

object NotificationBufferStore {
    private const val FILE_NAME = "notification_buffer.jsonl"
    private const val MAX_ITEMS = 120

    @Synchronized
    fun append(context: Context, json: String): Boolean {
        val file = File(context.filesDir, FILE_NAME)
        val items = if (file.exists()) file.readLines().filter { it.isNotBlank() }.toMutableList() else mutableListOf()
        val key = try {
            JSONObject(json).optString("notif_key")
        } catch (_: Throwable) {
            ""
        }
        if (key.isNotBlank() && items.any { existing ->
                try {
                    JSONObject(existing).optString("notif_key") == key
                } catch (_: Throwable) {
                    false
                }
            }
        ) return false
        items.add(json)
        val bounded = items.takeLast(MAX_ITEMS)
        file.writeText(bounded.joinToString(separator = "\n", postfix = if (bounded.isEmpty()) "" else "\n"))
        return true
    }

    @Synchronized
    fun drain(context: Context): List<String> {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.exists()) return emptyList()
        val lines = file.readLines()
        file.writeText("")
        return lines
    }

    /**
     * Remove todo conteúdo do buffer sem retornar os itens.
     */
    @Synchronized
    fun clear(context: Context) {
        val file = File(context.filesDir, FILE_NAME)
        if (file.exists()) {
            file.writeText("")
        }
    }
}
