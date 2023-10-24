import 'dart:async';
import 'dart:math' hide Rectangle;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/experimental.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/sprite.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maze_builder/maze_builder.dart';

final random = Random();
final cam = CameraComponent.withFixedResolution(width: 320, height: 180);
final cam2 = CameraComponent.withFixedResolution(width: 1280, height: 720);
void main() => runApp(const GameWidget.controlled(gameFactory: Lost.new));

class Lost extends Forge2DGame
    with HasKeyboardHandlerComponents, MouseMovementDetector, TapCallbacks {
  Lost() : super(cameraComponent: cam);

  @override
  Color backgroundColor() => const Color.fromARGB(246, 152, 15, 15);

  final mazeSize = 10;
  double get zoom => camera.viewfinder.zoom;
  double get wallWidth => 120 / zoom;
  double get wallThickness => 20 / zoom;
  double get wallSize => mazeSize * wallWidth;
  Vector2 get virtualSize => camera.viewport.virtualSize * 0.5 / zoom;

  final maze = Maze();
  final player = Player();

  @override
  Future<void> onLoad() async {
    await images.loadAll(['ss.png', 'sw.png', 'zw.png']);
    world = Forge2DWorld(children: [maze, player], gravity: Vector2.zero());
    cam2.world = world;
    cam2.viewfinder.anchor = Anchor.topLeft;
    cam2.viewfinder.position = Vector2.all(-10);
    add(cam2);
    camera.setBounds(
      Rectangle.fromLTRB(
        virtualSize.x,
        virtualSize.y,
        wallSize - virtualSize.x,
        wallSize - virtualSize.y,
      ),
    );
  }

  @override
  void onMouseMove(PointerHoverInfo info) {
    player.body.setTransform(
      player.body.position,
      (screenToWorld(info.eventPosition.global) - player.position)
          .screenAngle(),
    );
  }

  @override
  void onTapDown(TapDownEvent event) => player.shoot();

  SpriteSheet getSpriteSheet(String s, int r, int c) {
    return SpriteSheet.fromColumnsAndRows(
      image: images.fromCache(s),
      rows: r,
      columns: c,
    );
  }
}

class Maze extends BodyComponent<Lost> {
  @override
  Body createBody() {
    paint.color = Colors.black;
    final maze = generate(width: game.mazeSize, height: game.mazeSize, seed: 5);
    final body = world.createBody(BodyDef(userData: this));
    for (var i = 0; i < maze.length; i++) {
      for (var j = 0; j < maze[i].length; j++) {
        final cell = maze[i][j];
        if (cell.top) {
          _createFixture(body, i, j + 0.5, 0);
        }
        if (cell.right) {
          _createFixture(body, i + 0.5, j + 1, pi * 0.5);
        }
        if (cell.bottom) {
          _createFixture(body, i + 1, j + 0.5, 0);
        }
        if (cell.left) {
          _createFixture(body, i + 0.5, j, pi * 0.5);
        }
        if (i > 1 && j > 1 && random.nextBool() && random.nextBool()) {
          world.add(
            Zombie(
              Vector2((j + 0.5) * game.wallWidth, (i + 0.5) * game.wallWidth),
            ),
          );
        }
      }
    }
    return body;
  }

  void _createFixture(Body b, num i, num j, double angle) {
    b.createFixtureFromShape(
      PolygonShape()
        ..setAsBox(
          game.wallWidth * 0.5,
          game.wallThickness * 0.5,
          Vector2(j * game.wallWidth, i * game.wallWidth),
          angle,
        ),
    );
  }
}

enum State { walk, shoot }

class Player extends BodyComponent<Lost> with KeyboardHandler {
  final _moveSpeed = 600.0;
  final _dir = Vector2.zero();
  final _gunPoint = PositionComponent(position: Vector2(0.7, -2.4));
  late final SpriteAnimationGroupComponent<State> _anim;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final s1 = game.getSpriteSheet('sw.png', 1, 17);
    final s2 = game.getSpriteSheet('ss.png', 1, 17);
    _anim = SpriteAnimationGroupComponent<State>(
      animations: {
        State.walk: s1.createAnimation(row: 0, stepTime: 0.1),
        State.shoot: s2.createAnimation(row: 0, stepTime: 0.08, loop: false),
      },
      size: Vector2.all(5),
      current: State.walk,
      anchor: Anchor.center,
    );
    await addAll([_anim, _gunPoint]);

    final shootTicker = _anim.animationTickers![State.shoot]!;
    shootTicker.onComplete = () {
      shootTicker.reset();
      _anim.current = State.walk;
    };

    camera.follow(this);
    renderBody = false;
  }

  @override
  Body createBody() {
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: Vector2.all(game.wallWidth * 0.5),
        userData: this,
      ),
    );
    body.createFixtureFromShape(
      CircleShape()
        ..radius = 1
        ..position.setValues(0, 0.8),
    );
    body.createFixtureFromShape(
      CircleShape()
        ..radius = 1.2
        ..position.setValues(0.4, -0.9),
    );
    return body;
  }

  @override
  void update(double dt) {
    if (_anim.current == State.walk) {
      _anim.animationTicker!.paused = _dir.isZero();
    } else {
      _dir.scale(0.25);
    }
    body.linearVelocity = _dir * _moveSpeed * dt;
  }

  @override
  bool onKeyEvent(RawKeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _dir.setAll(0);
    _dir.x += keysPressed.contains(LogicalKeyboardKey.keyA) ? -1 : 0;
    _dir.x += keysPressed.contains(LogicalKeyboardKey.keyD) ? 1 : 0;
    _dir.y += keysPressed.contains(LogicalKeyboardKey.keyW) ? -1 : 0;
    _dir.y += keysPressed.contains(LogicalKeyboardKey.keyS) ? 1 : 0;
    _dir.normalize();
    return super.onKeyEvent(event, keysPressed);
  }

  void shoot() {
    if (_anim.current != State.shoot) {
      _anim.current = State.shoot;
      world.add(Bullet(position, Vector2(0, -1)..rotate(angle)));
    }
  }
}

class Zombie extends BodyComponent<Lost> with ContactCallbacks {
  Zombie(this.initalPosition);
  Vector2 initalPosition;
  final _speed = 8.0;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final spriteSheet = game.getSpriteSheet('zw.png', 1, 11);
    final anim = spriteSheet.createAnimation(row: 0, stepTime: 0.1);
    await add(
      SpriteAnimationComponent(
        animation: anim,
        size: Vector2.all(4),
        anchor: Anchor.center,
      ),
    );
    renderBody = false;
  }

  @override
  Body createBody() {
    final initalAngle = pi * random.nextDouble();
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: initalPosition,
        userData: this,
        angle: initalAngle,
        linearVelocity: Vector2(0, 1)
          ..scale(_speed)
          ..rotate(initalAngle),
      ),
    );
    return body..createFixtureFromShape(CircleShape()..radius = 1);
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is Maze || other is Zombie) {
      final newAngle = random.nextDouble();
      body.linearVelocity = Vector2(0, 1)
        ..scale(_speed)
        ..rotate(newAngle);
    }
    super.beginContact(other, contact);
  }
}

class Bullet extends BodyComponent with ContactCallbacks {
  Bullet(this.initalPosition, this.direction);

  final Vector2 initalPosition;
  final Vector2 direction;
  final _speed = 50.0;

  @override
  Body createBody() {
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        bullet: true,
        position: initalPosition,
        linearVelocity: direction.scaled(_speed),
        userData: this,
      ),
    );
    final fixtureDef = FixtureDef(CircleShape()..radius = 0.1, isSensor: true);
    return body..createFixture(fixtureDef);
  }

  @override
  void beginContact(Object other, Contact contact) {
    super.beginContact(other, contact);

    if (other is Zombie) {
      removeFromParent();
      other.removeFromParent();
    } else if (other is Maze) {
      removeFromParent();
    }
  }
}
