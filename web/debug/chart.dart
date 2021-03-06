import 'dart:html' as html;
import 'dart:svg' as svg;

import 'package:malison/malison.dart';

import 'package:hauberk/src/engine.dart';
import 'package:hauberk/src/content/item/affixes.dart';
import 'package:hauberk/src/content/item/floor_drops.dart';
import 'package:hauberk/src/content/item/items.dart';
import 'package:hauberk/src/content/monster/monsters.dart';

import 'histogram.dart';

final _svg = html.querySelector("svg") as svg.SvgElement;

final _breedCounts = List.generate(Option.maxDepth, (_) => Histogram<String>());
List<String> _breedNames;

final _itemCounts = List.generate(Option.maxDepth, (_) => Histogram<String>());
List<String> _itemNames;

final _affixCounts = List.generate(Option.maxDepth, (_) => Histogram<String>());
List<String> _affixNames;

final _monsterDepthCounts =
    List.generate(Option.maxDepth, (_) => Histogram<String>());

final _floorDropCounts =
    List.generate(Option.maxDepth, (_) => Histogram<String>());

final _colors = <String, String>{};

const batchSize = 1000;
const chartWidth = 600;
const barSize = 6;

String get shownData {
  var select = html.querySelector("select") as html.SelectElement;
  return select.value;
}

main() {
  Items.initialize();
  Affixes.initialize();
  Monsters.initialize();
  FloorDrops.initialize();

  for (var itemType in Items.types.all) {
    _colors[itemType.name] = (itemType.appearance as Glyph).fore.cssColor;
    _colors["${itemType.name} (ego)"] =
        (itemType.appearance as Glyph).fore.blend(Color.black, 0.5).cssColor;
  }

  for (var breed in Monsters.breeds.all) {
    _colors[breed.name] = (breed.appearance as Glyph).fore.cssColor;
  }

  for (var i = -100; i <= 100; i++) {
    _colors[i.toString()] = "hsl(${(i + 100) * 10 % 360}, 70%, 40%)";
  }

  _svg.onClick.listen((_) => _generateMore());

  var select = html.querySelector("select") as html.SelectElement;
  select.onChange.listen((_) {
    switch (shownData) {
      case "breeds":
        _drawBreeds();
        break;

      case "item-types":
        _drawItems();
        break;

      case "affixes":
        _drawAffixes();
        break;

      case "monster-depths":
        _drawMonsterDepths();
        break;

      case "floor-drops":
        _drawFloorDrops();
        break;

      default:
        throw "Unknown select value '$shownData'.";
    }
  });

  _generateMore();
}

void _generateMore() {
  switch (shownData) {
    case "breeds":
      _moreBreeds();
      break;

    case "item-types":
      _moreItems();
      break;

    case "affixes":
      _moreAffixes();
      break;

    case "monster-depths":
      _moreMonsterDepths();
      break;

    case "floor-drops":
      _moreFloorDrops();
      break;

    default:
      throw "Unknown select value '$shownData'.";
  }
}

void _moreBreeds() {
  for (var depth = 1; depth <= Option.maxDepth; depth++) {
    var histogram = _breedCounts[depth - 1];

    for (var i = 0; i < batchSize; i++) {
      var breed = Monsters.breeds.tryChoose(depth);
      if (breed == null) continue;

      // Take groups and minions into account
      for (var spawn in breed.spawnAll()) {
        histogram.add(spawn.name);
      }
    }
  }

  _drawBreeds();
}

void _moreItems() {
  for (var depth = 1; depth <= Option.maxDepth; depth++) {
    var histogram = _itemCounts[depth - 1];

    for (var i = 0; i < batchSize; i++) {
      var itemType = Items.types.tryChoose(depth);
      if (itemType == null) continue;

      var item = Affixes.createItem(itemType, depth);
      if (item.prefix != null || item.suffix != null) {
        histogram.add("${itemType.name} (ego)");
      } else {
        histogram.add(itemType.name);
      }
    }
  }

  _drawItems();
}

void _moreAffixes() {
  for (var depth = 1; depth <= Option.maxDepth; depth++) {
    var histogram = _affixCounts[depth - 1];

    for (var i = 0; i < batchSize; i++) {
      var itemType = Items.types.tryChoose(depth, tag: "equipment");
      if (itemType == null) continue;

      // Don't count items that can't have affixes.
      if (!Items.types.hasTag(itemType.name, "equipment")) {
        continue;
      }

      var item = Affixes.createItem(itemType, depth);

      if (item.prefix != null) histogram.add("${item.prefix.name} _");
      if (item.suffix != null) histogram.add("_ ${item.suffix.name}");
      if (item.prefix == null && item.suffix == null) histogram.add("(none)");
    }
  }

  _drawAffixes();
}

void _moreMonsterDepths() {
  for (var depth = 1; depth <= Option.maxDepth; depth++) {
    var histogram = _monsterDepthCounts[depth - 1];

    for (var i = 0; i < batchSize; i++) {
      var breed = Monsters.breeds.tryChoose(depth);
      if (breed == null) continue;

      histogram.add((breed.depth - depth).toString());
    }
  }

  _drawMonsterDepths();
}

void _moreFloorDrops() {
  for (var depth = 1; depth <= Option.maxDepth; depth++) {
    var histogram = _floorDropCounts[depth - 1];

    for (var i = 0; i < batchSize; i++) {
      var drop = FloorDrops.choose(depth);
      drop.drop.spawnDrop(depth, (item) {
        histogram.add(item.type.name);
      });
    }
  }

  _drawFloorDrops();
}

void _drawBreeds() {
  if (_breedNames == null) {
    _breedNames = Monsters.breeds.all.map((breed) => breed.name).toList();
    _breedNames.sort((a, b) {
      var aBreed = Monsters.breeds.find(a);
      var bBreed = Monsters.breeds.find(b);

      if (aBreed.depth != bBreed.depth) {
        return aBreed.depth.compareTo(bBreed.depth);
      }

      if (aBreed.experience != bBreed.experience) {
        return aBreed.experience.compareTo(bBreed.experience);
      }

      return aBreed.name.compareTo(bBreed.name);
    });
  }

  _redraw(_breedCounts, _breedNames, (label) {
    var breed = Monsters.breeds.find(label);
    return '$label (depth ${breed.depth})';
  });
}

void _drawItems() {
  _initializeItemNames();
  _redraw(_itemCounts, _itemNames, (label) {
    var typeName = label;
    if (typeName.endsWith(" (ego)")) {
      typeName = typeName.substring(0, typeName.length - 6);
    }

    var type = Items.types.find(typeName);
    return '$label (depth ${type.depth})';
  });
}

void _drawAffixes() {
  if (_affixNames == null) {
    _affixNames = ["(none)"];
    _affixNames.addAll(Affixes.prefixes.all.map((affix) => "${affix.name} _"));
    _affixNames.addAll(Affixes.suffixes.all.map((affix) => "_ ${affix.name}"));

    // TODO: Sort by depth and rarity?
    _affixNames.sort();

    for (var i = 0; i < _affixNames.length; i++) {
      _colors[_affixNames[i]] = 'hsl(${i * 17 % 360}, 50%, 50%)';
    }
  }

  _redraw(_affixCounts, _affixNames, (label) => label);
}

void _drawMonsterDepths() {
  var labels = <String>[];
  for (var i = -100; i <= 100; i++) {
    labels.add("$i");
  }

  _redraw(_monsterDepthCounts, labels, (label) {
    var relative = int.parse(label);
    if (relative == 0) return "same";
    if (relative < 0) return "${-relative} shallower monster";
    return "$label deeper monster";
  });
}

void _drawFloorDrops() {
  _initializeItemNames();
  _redraw(_floorDropCounts, _itemNames, (label) {
    var type = Items.types.find(label);
    return '$label (depth ${type.depth})';
  });
}

void _initializeItemNames() {
  if (_itemNames == null) {
    _itemNames = Items.types.all.map((type) => type.name).toList();
    _itemNames.sort((a, b) {
      var aType = Items.types.find(a);
      var bType = Items.types.find(b);

      if (aType.depth != bType.depth) {
        return aType.depth.compareTo(bType.depth);
      }

      if (aType.price != bType.price) {
        return aType.price.compareTo(bType.price);
      }

      return aType.name.compareTo(bType.name);
    });

    _itemNames.addAll(_itemNames.map((name) => "$name (ego)").toList());
  }
}

void _redraw(List<Histogram<String>> histograms, List<String> labels,
    String describe(String label)) {
  var buffer = StringBuffer();

  for (var depth = 0; depth < Option.maxDepth; depth++) {
    var histogram = histograms[depth];
    var total = 0;
    for (var label in labels) {
      total += histogram.count(label);
    }

    var x = chartWidth.toDouble();
    var y = depth * barSize;
    var right = chartWidth.toDouble();

    for (var label in labels) {
      var count = histogram.count(label);
      if (count == 0) continue;

      var fraction = count / total;
      var percent = ((fraction * 1000).toInt() / 10).toStringAsFixed(1);
      x -= fraction * chartWidth;
      buffer.write('<rect fill="${_colors[label]}" x="$x" y="$y" '
          'width="${right - x}" height="$barSize">');
      buffer.write('<title>depth ${depth + 1}: ${describe(label)} $percent% '
          '($count)</title></rect>');

      right = x;
    }
  }

  _svg.setInnerHtml(buffer.toString());
}
