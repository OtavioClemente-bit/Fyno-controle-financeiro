package com.example.controle_financeiro.notifications

import java.text.Normalizer

data class ParsedTransactionNotification(
    val amount: Double,
    val isIncome: Boolean?,
    val method: String,
)

/**
 * Classificador local. Direções ambíguas continuam indo para revisão, mas
 * mensagens promocionais e dados sensíveis permanecem bloqueados.
 */
object TransactionNotificationParser {
    private val amountRegex = Regex(
        pattern = "(?i)(?:(?:R\\$|BRL)\\s*([0-9]{1,3}(?:\\.[0-9]{3})+(?:,[0-9]{2})?|[0-9]+(?:,[0-9]{2})?)|([0-9]{1,3}(?:\\.[0-9]{3})+(?:,[0-9]{2})?|[0-9]+(?:,[0-9]{2})?)\\s*reais?)",
    )

    private val sensitiveTerms = listOf(
        "codigo de seguranca", "codigo de verificacao", "token", "senha",
        "tentativa de acesso", "novo acesso", "login", "autenticacao",
    )

    private val nonTransactionTerms = listOf(
        "oferta", "promocao", "pre-aprovado", "emprestimo disponivel",
        "fatura fechou", "fatura disponivel", "vencimento", "limite disponivel",
        "boleto disponivel", "pague sua fatura", "saldo disponivel", "seu saldo",
    )

    private val incomeTerms = listOf(
        "pix recebido", "pix que voce recebeu", "transferencia recebida",
        "deposito recebido", "valor recebido", "foi creditado", "creditado em sua conta",
        "estorno recebido", "cashback recebido", "voce recebeu", "recebimento confirmado",
        "credito em conta", "entrada em conta",
    )

    private val expenseTerms = listOf(
        "compra aprovada", "compra realizada", "compra no debito", "cartao utilizado",
        "cartao usado", "cartao foi usado", "compra confirmada", "compra autorizada",
        "pagamento realizado", "pagamento aprovado", "valor debitado", "debitado da sua conta",
        "pagamento efetuado", "pagamento concluido", "pagamento feito",
        "pix enviado", "pix realizado", "transferencia enviada", "transferencia realizada",
        "pix transferido", "voce fez um pix", "transferencia concluida",
        "saque realizado", "voce pagou", "voce enviou", "compra efetuada",
        "transacao aprovada", "lancamento no cartao", "pagamento confirmado",
    )

    private val genericTransactionTerms = listOf(
        "compra", "pagamento", "pix", "transferencia", "transacao",
        "movimentacao", "debito", "credito em conta", "saque", "estorno",
    )

    fun parse(raw: String): ParsedTransactionNotification? {
        val normalized = normalize(raw)
        if (normalized.isBlank() || sensitiveTerms.any(normalized::contains)) return null

        val amountMatch = amountRegex.find(raw.replace('\u00A0', ' ')) ?: return null
        val amountText = amountMatch.groupValues.drop(1).firstOrNull(String::isNotBlank)
            ?: return null
        val amount = parseAmount(amountText) ?: return null
        if (amount <= 0.0) return null

        val looksLikePurchase = normalized.contains("compra") &&
            listOf("aprovada", "realizada", "confirmada", "autorizada", "cartao", "debito")
                .any(normalized::contains)
        val looksLikePayment = normalized.contains("pagamento") &&
            listOf("aprovado", "realizado", "efetuado", "concluido", "feito")
                .any(normalized::contains)
        val looksLikeSentPix = normalized.contains("pix") &&
            listOf("enviado", "realizado", "transferido", "feito").any(normalized::contains)

        val hasStrongTransactionSignal = incomeTerms.any(normalized::contains) ||
            expenseTerms.any(normalized::contains) ||
            looksLikePurchase || looksLikePayment || looksLikeSentPix
        if (!hasStrongTransactionSignal && nonTransactionTerms.any(normalized::contains)) return null
        if (!hasStrongTransactionSignal && genericTransactionTerms.none(normalized::contains)) return null

        val isIncome = when {
            incomeTerms.any(normalized::contains) -> true
            expenseTerms.any(normalized::contains) || looksLikePurchase || looksLikePayment || looksLikeSentPix -> false
            else -> null
        }

        val method = when {
            normalized.contains("pix") -> "Pix"
            normalized.contains("debito") || normalized.contains("debitado") -> "Débito"
            normalized.contains("credito") || normalized.contains("cartao") || normalized.contains("compra") -> "Crédito"
            normalized.contains("transferencia") -> "Transferência"
            normalized.contains("saque") -> "Dinheiro"
            else -> if (isIncome == true) "Transferência" else "Outro"
        }

        return ParsedTransactionNotification(amount, isIncome, method)
    }

    private fun parseAmount(value: String): Double? {
        val groupedInteger = Regex("^[0-9]{1,3}(?:\\.[0-9]{3})+$").matches(value)
        val canonical = when {
            value.contains(',') -> value.replace(".", "").replace(',', '.')
            groupedInteger -> value.replace(".", "")
            else -> value
        }
        return canonical.toDoubleOrNull()
    }

    private fun normalize(value: String): String {
        val decomposed = Normalizer.normalize(value.lowercase(), Normalizer.Form.NFD)
        return decomposed.replace(Regex("\\p{M}+"), "").replace(Regex("\\s+"), " ").trim()
    }
}
