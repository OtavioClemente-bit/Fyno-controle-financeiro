package com.example.controle_financeiro.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransactionNotificationParserTest {
    @Test
    fun detectsDebitCardPurchase() {
        val parsed = TransactionNotificationParser.parse(
            "Compra no débito aprovada no valor de R$ 1.234,56",
        )!!

        assertEquals(1234.56, parsed.amount, 0.001)
        assertEquals(false, parsed.isIncome)
        assertEquals("Débito", parsed.method)
    }

    @Test
    fun detectsIncomingPix() {
        val parsed = TransactionNotificationParser.parse(
            "Você recebeu um Pix de R$ 89,90",
        )!!

        assertEquals(89.90, parsed.amount, 0.001)
        assertEquals(true, parsed.isIncome)
        assertEquals("Pix", parsed.method)
    }

    @Test
    fun rejectsSecurityCodeEvenWithCurrencyText() {
        assertNull(
            TransactionNotificationParser.parse(
                "Código de verificação 123456 para confirmar pagamento de R$ 50,00",
            ),
        )
    }

    @Test
    fun rejectsMarketingAndAmbiguousAmounts() {
        assertNull(TransactionNotificationParser.parse("Oferta de crédito de R$ 5.000,00"))
        assertNull(TransactionNotificationParser.parse("Seu saldo é R$ 250,00"))
    }

    @Test
    fun acceptsPurchaseEvenWhenNotificationAlsoShowsAvailableLimit() {
        val parsed = TransactionNotificationParser.parse(
            "Compra aprovada de R$ 72,40. Limite disponível: R$ 1.900,00",
        )!!

        assertEquals(72.40, parsed.amount, 0.001)
        assertEquals(false, parsed.isIncome)
    }

    @Test
    fun acceptsBrlAndCardUsedWording() {
        val parsed = TransactionNotificationParser.parse(
            "Seu cartão foi usado em uma compra de BRL 1.234,56",
        )!!

        assertEquals(1234.56, parsed.amount, 0.001)
        assertEquals(false, parsed.isIncome)
        assertEquals("Crédito", parsed.method)
    }

    @Test
    fun parsesWholeThousandsWithoutCents() {
        val parsed = TransactionNotificationParser.parse(
            "Transferência realizada no valor de R$ 1.234",
        )!!

        assertEquals(1234.0, parsed.amount, 0.001)
        assertEquals(false, parsed.isIncome)
    }

    @Test
    fun keepsAmbiguousBankTransactionForManualReview() {
        val parsed = TransactionNotificationParser.parse(
            "Movimentação de R$ 37,45 realizada na sua conta",
        )!!

        assertEquals(37.45, parsed.amount, 0.001)
        assertNull(parsed.isIncome)
        assertEquals("Outro", parsed.method)
    }

    @Test
    fun acceptsAmountWrittenInReais() {
        val parsed = TransactionNotificationParser.parse(
            "Pix recebido: 150,00 reais",
        )!!

        assertEquals(150.0, parsed.amount, 0.001)
        assertEquals(true, parsed.isIncome)
    }
}
