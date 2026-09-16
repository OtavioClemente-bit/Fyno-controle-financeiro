import 'package:flutter/material.dart';

class BankAppDefinition {
  final String name;
  final List<String> packageNames;
  final Color color;
  final String initials;

  const BankAppDefinition({
    required this.name,
    required String packageName,
    this.packageNames = const [],
    required this.color,
    required this.initials,
  }) : _primaryPackageName = packageName;

  final String _primaryPackageName;

  String get packageName => _primaryPackageName;

  Iterable<String> get allPackageNames sync* {
    yield _primaryPackageName;
    yield* packageNames;
  }

  bool matchesPackage(String packageName) =>
      allPackageNames.contains(packageName);
}

/// Catálogo explícito evita a permissão ampla de inventário de apps instalados.
const bankAppCatalog = <BankAppDefinition>[
  BankAppDefinition(
    name: 'Nubank',
    packageName: 'com.nu.production',
    color: Color(0xFF820AD1),
    initials: 'NU',
  ),
  BankAppDefinition(
    name: 'Itaú',
    packageName: 'com.itau',
    packageNames: ['com.itau.pers', 'com.itau.iti', 'com.itaucard.activity'],
    color: Color(0xFFEC7000),
    initials: 'IT',
  ),
  BankAppDefinition(
    name: 'Banco do Brasil',
    packageName: 'br.com.bb.android',
    packageNames: ['br.com.bb.android.pj'],
    color: Color(0xFFFFD600),
    initials: 'BB',
  ),
  BankAppDefinition(
    name: 'Bradesco',
    packageName: 'com.bradesco',
    packageNames: ['br.com.bradesco.cartoes', 'br.com.bradesco.next'],
    color: Color(0xFFCC092F),
    initials: 'BR',
  ),
  BankAppDefinition(
    name: 'Santander',
    packageName: 'com.santander.app',
    packageNames: ['com.santander.way', 'com.santandermovelempresarial.app'],
    color: Color(0xFFEC0000),
    initials: 'ST',
  ),
  BankAppDefinition(
    name: 'CAIXA',
    packageName: 'br.com.gabba.Caixa',
    packageNames: [
      'br.gov.caixa.superapp',
      'br.gov.caixa.tem',
      'br.com.gabba.CaixaTem',
    ],
    color: Color(0xFF0066A1),
    initials: 'CX',
  ),
  BankAppDefinition(
    name: 'Inter',
    packageName: 'br.com.intermedium',
    color: Color(0xFFFF7A00),
    initials: 'IN',
  ),
  BankAppDefinition(
    name: 'C6 Bank',
    packageName: 'com.c6bank.app',
    packageNames: ['com.c6bank.app.yellow'],
    color: Color(0xFF242424),
    initials: 'C6',
  ),
  BankAppDefinition(
    name: 'Mercado Pago',
    packageName: 'com.mercadopago.wallet',
    color: Color(0xFF00AEEF),
    initials: 'MP',
  ),
  BankAppDefinition(
    name: 'PicPay',
    packageName: 'com.picpay',
    color: Color(0xFF21C25E),
    initials: 'PP',
  ),
  BankAppDefinition(
    name: 'PagBank',
    packageName: 'br.com.uol.ps.myaccount',
    color: Color(0xFF00B27A),
    initials: 'PG',
  ),
];

Set<String> get allBankPackageNames =>
    bankAppCatalog.expand((bank) => bank.allPackageNames).toSet();

BankAppDefinition? bankByPackage(String packageName) {
  for (final bank in bankAppCatalog) {
    if (bank.matchesPackage(packageName)) return bank;
  }
  return null;
}
