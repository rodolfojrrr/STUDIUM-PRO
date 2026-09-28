import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_routine_active/core/rich_summary_document.dart';
import 'package:my_routine_active/widgets/summary_embed_widget.dart';

void main() {
  testWidgets('a imagem incorporada mantém o provedor ao reconstruir o editor',
      (tester) async {
    const embed = SummaryEmbed(
      id: 'imagem-estavel',
      type: SummaryEmbed.imageType,
      base64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final provider = SummaryInlineImageCache.providerFor(embed);
    expect(provider, isNotNull);
    expect(identical(provider, SummaryInlineImageCache.providerFor(embed)),
        isTrue);

    Widget page() => const MaterialApp(
          home: Scaffold(
            body: SummaryEmbedWidget(embed: embed, maxWidth: 360),
          ),
        );
    await tester.pumpWidget(page());
    final first = tester.widget<Image>(find.byType(Image));
    await tester.pumpWidget(page());
    final second = tester.widget<Image>(find.byType(Image));
    expect(identical(first.image, second.image), isTrue);
    expect(tester.takeException(), isNull);
  });
}
