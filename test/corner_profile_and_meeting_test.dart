import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';

void main() {
  group('Meeting central sashes and corner frame translations', () {
    test('Translates التقاء الظرفتين الوسطيتين (Batmo central) in all languages', () {
      expect(
        Localization.translate('التقاء الظرفتين الوسطيتين (Batmo central)', AppLanguage.arabic),
        'التقاء الظرفتين الوسطيتين (Batmo central)',
      );
      expect(
        Localization.translate('التقاء الظرفتين الوسطيتين (Batmo central)', AppLanguage.french),
        'Rencontre face à face (Batmo central)',
      );
      expect(
        Localization.translate('التقاء الظرفتين الوسطيتين (Batmo central)', AppLanguage.english),
        'Face to face meeting (Batmo central)',
      );
    });

    test('Translates إطار زاوية 90° and related strings', () {
      expect(
        Localization.translate('إطار زاوية 90°', AppLanguage.arabic),
        'إطار زاوية 90°',
      );
      expect(
        Localization.translate('إطار زاوية 90°', AppLanguage.french),
        'Cadre angle 90°',
      );
      expect(
        Localization.translate('إطار زاوية 90°', AppLanguage.english),
        '90° corner frame',
      );

      expect(
        Localization.translate('إطار زاوية 90° معتمد في جدول الكمية والتكلفة', AppLanguage.arabic),
        'إطار زاوية 90° معتمد في جدول الكمية والتكلفة',
      );
      expect(
        Localization.translate('إطار زاوية 90° معتمد في جدول الكمية والتكلفة', AppLanguage.french),
        'Cadre angle 90° appliqué au devis',
      );
      expect(
        Localization.translate('إطار زاوية 90° معتمد في جدول الكمية والتكلفة', AppLanguage.english),
        '90° corner frame applied in BOM',
      );
    });
  });

  group('Profile angle junction frame selection in WindowModel', () {
    test('getProfileAngleJunctionFrames returns empty when usesProfileAngle is false', () {
      final model = WindowModel(db: SqlDatabase());
      expect(model.getProfileAngleJunctionFrames().isEmpty, isTrue);
    });

    test('getProfileAngleJunctionFrames returns compatible frame when corner profile is active', () {
      final model = WindowModel(db: SqlDatabase());
      model.width = 2000;
      model.height = 1200;

      // Two coupled frames: the corner profile goes between them.
      final pt = model.profileThickness;
      model.zones = [
        WindowZone(
          id: 'zone_left',
          boundary: Rect.fromLTRB(pt, pt, 1000 - pt, 1200 - pt),
          content: ZoneContent.singleSash,
        ),
        WindowZone(
          id: 'zone_right',
          boundary: Rect.fromLTRB(1000 + pt, pt, 2000 - pt, 1200 - pt),
          content: ZoneContent.singleSash,
        ),
      ];
      model.coupleFrames = true;

      final openingSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'Opening Series 45',
        type: 'opening',
        sections: [
          AluminumSection(
            id: 101,
            seriesId: 1,
            code: 'P101',
            name: 'Cadre 45 avec couvre-joint',
            type: 'frame',
            thickness: 45,
            visibleWidth: 45,
            couvreJointWidth: 20,
          ),
          AluminumSection(
            id: 102,
            seriesId: 1,
            code: 'P102',
            name: 'Cadre 45 sans couvre-joint',
            type: 'frame',
            thickness: 45,
            visibleWidth: 45,
            couvreJointWidth: 0,
            // Only a frame that can never carry a cover sits against the
            // aluminium corner tube.
            allowsSideCover: false,
          ),
        ],
      );

      model.activeSeries = openingSeries;
      // The current frame carries a cover; a frame already without cover
      // needs no switch and would yield no compatible frame.
      model.frameOverride = openingSeries.sections.first.toMap();
      model.hasSideCovers = true;
      model.profileAngleJunctionsDisabled = false;
      model.profileAngleJunctions = {0};

      final junctionFrames = model.getProfileAngleJunctionFrames();
      expect(junctionFrames.isNotEmpty, isTrue);
      final first = junctionFrames.values.first;
      expect(first.sliding, isFalse);
      expect(first.section.id, 102);
      expect(first.section.name, 'Cadre 45 sans couvre-joint');
    });

    test('only a frame that can never carry a cover fits an aluminium corner', () {
      AluminumSection frame(int id, {bool allows = true, double cover = 0}) =>
          AluminumSection(
            id: id,
            seriesId: 1,
            code: 'F$id',
            name: 'Cadre $id',
            type: 'frame',
            thickness: 45,
            visibleWidth: 45,
            couvreJointWidth: cover,
            allowsSideCover: allows,
          );
      final integrated = frame(1, cover: 20);
      final acceptsCover = frame(2);
      final plain = frame(3, allows: false);

      final aluminium = WindowModel(db: SqlDatabase())
        ..activeSeries = AluminumSeries(
          id: 1,
          profileId: 1,
          name: 'Série 40',
          type: 'opening',
          sections: [integrated, acceptsCover, plain],
        );
      expect(aluminium.frameFitsProfileAngle(integrated), isFalse);
      expect(aluminium.frameFitsProfileAngle(acceptsCover), isFalse);
      expect(aluminium.frameFitsProfileAngle(plain), isTrue);
      // A frame accepting a cover is usable: its jamb against the corner is
      // cut from the plain frame of the series.
      expect(aluminium.frameUsableWithProfileAngle(acceptsCover), isTrue);

      final pvc = WindowModel(db: SqlDatabase())
        ..activeSeries = AluminumSeries(
          id: 2,
          profileId: 1,
          name: 'PVC 70',
          type: 'pvc',
          sections: [integrated, acceptsCover],
        );
      expect(pvc.frameFitsProfileAngle(acceptsCover), isTrue);
      expect(pvc.frameFitsProfileAngle(integrated), isFalse);
    });

    test('getProfileAngleJunctionFrames returns two frames when two different series meet at junction', () {
      final model = WindowModel(db: SqlDatabase());
      model.width = 2000;
      model.height = 1200;

      model.zones = [
        WindowZone(
          id: 'zone_left',
          // Two physical frames: each glazed zone sits inside its own frame
          // profiles, so the frames meet at one junction.
          boundary: const Rect.fromLTRB(40, 40, 960, 1160),
          content: ZoneContent.singleSash,
        ),
        WindowZone(
          id: 'zone_right',
          boundary: const Rect.fromLTRB(1040, 40, 1960, 1160),
          content: ZoneContent.slidingSash,
        ),
      ];

      final openingSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'Opening Series 45',
        type: 'opening',
        sections: [
          AluminumSection(
            id: 101,
            seriesId: 1,
            code: 'P101',
            name: 'Cadre Ouvrant avec couvre-joint',
            type: 'frame',
            thickness: 45,
            visibleWidth: 45,
            couvreJointWidth: 20,
          ),
          AluminumSection(
            id: 102,
            seriesId: 1,
            code: 'P102',
            name: 'Cadre Ouvrant sans couvre-joint',
            type: 'frame',
            thickness: 45,
            visibleWidth: 45,
            couvreJointWidth: 0,
            // Only a frame that can never carry a cover sits against the
            // aluminium corner tube.
            allowsSideCover: false,
          ),
        ],
      );

      final slidingSeries = AluminumSeries(
        id: 2,
        profileId: 2,
        name: 'Sliding Series 60',
        type: 'sliding',
        sections: [
          AluminumSection(
            id: 201,
            seriesId: 2,
            code: 'P201',
            name: 'Cadre Coulissant avec couvre-joint',
            type: 'frame',
            thickness: 60,
            visibleWidth: 60,
            couvreJointWidth: 25,
          ),
          AluminumSection(
            id: 202,
            seriesId: 2,
            code: 'P202',
            name: 'Cadre Coulissant sans couvre-joint',
            type: 'frame',
            thickness: 60,
            visibleWidth: 60,
            couvreJointWidth: 0,
            // Only a frame that can never carry a cover sits against the
            // aluminium corner tube.
            allowsSideCover: false,
          ),
        ],
      );

      model.activeSeries = openingSeries;
      model.activeSlidingSeries = slidingSeries;
      model.coupleFrames = true;
      model.frameOverride = openingSeries.sections.first.toMap();
      model.slidingFrameOverride = slidingSeries.sections.first.toMap();
      model.hasSideCovers = true;
      model.profileAngleJunctionsDisabled = false;
      model.profileAngleJunctions = {0};

      final junctionFrames = model.getProfileAngleJunctionFrames();
      expect(junctionFrames.length, 2);
      expect(junctionFrames.containsKey('opening:102'), isTrue);
      expect(junctionFrames.containsKey('sliding:202'), isTrue);
    });
  });
}
