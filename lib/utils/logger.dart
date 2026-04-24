import 'package:logger/logger.dart';

/// Instância única (Singleton) do Logger para o projeto Calibre Drive.
/// Centralizamos a configuração aqui para manter o terminal organizado.
final logger = Logger(
  printer: PrettyPrinter(
    // Quantas linhas da "pilha de chamadas" (stacktrace) mostrar.
    // 0 significa que ele mostra apenas a sua mensagem, sem indicar
    // em qual função o log foi chamado. Bom para manter o terminal limpo.
    methodCount: 0,

    // Quando houver um ERRO (logger.e), ele mostra até 8 linhas do
    // rastro de onde o erro aconteceu. Vital para debugar crashes.
    errorMethodCount: 8,

    // Largura da linha horizontal que separa os logs no terminal.
    // 120 é um valor padrão bom para a maioria dos monitores.
    lineLength: 120,

    // (Verde = Info, Vermelho = Erro, Amarelo = Warning, Azul = Debug).
    // Ativa cores no terminal.
    colors: true,

    // Adiciona um emoji automático no início de cada log.
    // 💡 para Info, 🐛 para Debug, ⛔ para Erro, etc. Facilitando o escaneamento visual.
    printEmojis: true,

    // DateTimeFormat.none -> Não mostra hora (limpo)
    // DateTimeFormat.onlyTimeAndSinceStart -> Mostra hora e tempo desde o início do app
    dateTimeFormat: DateTimeFormat.dateAndTime,
  ),
);
