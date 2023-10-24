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
final tp = TextPaint(style: const TextStyle(fontSize: 10));
final text = TextComponent(textRenderer: tp, anchor: Anchor.center);
final cam = CameraComponent.withFixedResolution(
  width: 320,
  height: 180,
  hudComponents: [text],
);
final cam2 = CameraComponent.withFixedResolution(width: 1280, height: 720);
void main() => runApp(const GameWidget.controlled(gameFactory: Lost.new));

class Lost extends Forge2DGame
    with HasKeyboardHandlerComponents, MouseMovementDetector, TapCallbacks {
  Lost() : super(cameraComponent: cam);

  @override
  Color backgroundColor() => const Color.fromARGB(255, 152, 15, 15);

  final mazeSize = 10;
  double get zoom => camera.viewfinder.zoom;
  double get wallW => 120 / zoom;
  double get wallT => 20 / zoom;
  double get wallSize => mazeSize * wallW;
  Vector2 get virtualSize => camera.viewport.virtualSize * 0.5 / zoom;
  var _elapsed = 0.0;

  final maze = Maze();
  final player = Player();

  @override
  Future<void> onLoad() async {
    text.position = cam.viewport.virtualSize * 0.5;
    text.text = 'Escape the maze';
    await images.loadAll(['ss.png', 'sw.png', 'zw.png']);
    world = Forge2DWorld(children: [maze, player], gravity: Vector2.zero());
    cam2.world = world;
    cam2.viewfinder.anchor = Anchor.topLeft;
    cam2.viewfinder.position = Vector2.all(-10);
    //add(cam2);
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
  void update(double dt) {
    super.update(dt);
    if (text.text.isNotEmpty) {
      _elapsed += dt;
      if (_elapsed > 3) {
        text.text = '';
        _elapsed = 0.0;
      }
    }
  }

  @override
  void onMouseMove(PointerHoverInfo info) {
    if (!player.dead) {
      player.body.setTransform(
        player.body.position,
        (screenToWorld(info.eventPosition.global) - player.position)
            .screenAngle(),
      );
    }
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
        if (i >= 1 && j >= 1 && random.nextBool() && random.nextBool()) {
          world.add(Zombie(Vector2(j + 0.5, i + 0.5)));
        }
      }
    }
    final row = random.nextInt(game.mazeSize).toDouble();
    world.add(Exit(Vector2(game.mazeSize - 0.5, row + 0.5)));
    return body;
  }

  void _createFixture(Body b, num i, num j, double angle) =>
      b.createFixtureFromShape(
        PolygonShape()
          ..setAsBox(
            game.wallW * 0.5,
            game.wallT * 0.5,
            Vector2(j * game.wallW, i * game.wallW),
            angle,
          ),
      );
}

enum State { walk, shoot }

class Player extends BodyComponent<Lost>
    with KeyboardHandler, ContactCallbacks {
  final _moveSpeed = 600.0;
  final _dir = Vector2.zero();
  bool dead = false;
  late final s1 = game.getSpriteSheet('sw.png', 1, 17);
  late final s2 = game.getSpriteSheet('ss.png', 1, 17);
  late final _anim = SpriteAnimationGroupComponent<State>(
    animations: {
      State.walk: s1.createAnimation(row: 0, stepTime: 0.1),
      State.shoot: s2.createAnimation(row: 0, stepTime: 0.08, loop: false),
    },
    size: Vector2.all(5),
    current: State.walk,
    anchor: Anchor.center,
  );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    await add(_anim);

    final shootTicker = _anim.animationTickers![State.shoot]!;
    shootTicker.onComplete = () {
      shootTicker.reset();
      _anim.current = State.walk;
    };

    camera.follow(this);
    renderBody = false;
  }

  @override
  Body createBody() => world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: Vector2.all(game.wallW * 0.5),
          userData: this,
        ),
      )
        ..createFixtureFromShape(
          CircleShape()
            ..radius = 1
            ..position.setValues(0, 0.8),
        )
        ..createFixtureFromShape(
          CircleShape()
            ..radius = 1.2
            ..position.setValues(0.4, -0.9),
        );

  @override
  void update(double dt) {
    if (_anim.current == State.walk) {
      _anim.animationTicker!.paused = _dir.isZero();
    } else {
      _dir.scale(0.5);
    }
    body.linearVelocity = _dir * _moveSpeed * dt;
  }

  @override
  bool onKeyEvent(RawKeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!dead) {
      _dir.setAll(0);
      _dir.x += keysPressed.contains(LogicalKeyboardKey.keyA) ? -1 : 0;
      _dir.x += keysPressed.contains(LogicalKeyboardKey.keyD) ? 1 : 0;
      _dir.y += keysPressed.contains(LogicalKeyboardKey.keyW) ? -1 : 0;
      _dir.y += keysPressed.contains(LogicalKeyboardKey.keyS) ? 1 : 0;
      _dir.normalize();
    }
    return super.onKeyEvent(event, keysPressed);
  }

  @override
  void beginContact(Object other, Contact contact) {
    super.beginContact(other, contact);
    if (other is Zombie) {
      text.text = 'You got caught by a zombie!';
      dead = true;
    }
  }

  void shoot() {
    if (_anim.current != State.shoot) {
      _anim.current = State.shoot;
      world.add(Bullet(position, Vector2(0, -1)..rotate(angle)));
    }
  }
}

class Zombie extends BodyComponent<Lost> implements RayCastCallback {
  Zombie(this.initalPosition);

  var _elapsed = 0.0;
  final _speed = 15.0;
  final Vector2 initalPosition;
  Vector2 get _target => Vector2(0, -5)..rotate(angle, center: position);

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
  Body createBody() => world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: initalPosition.scaled(game.wallW),
          userData: this,
          linearVelocity: Vector2(0, -1)..scale(_speed),
        ),
      )..createFixtureFromShape(CircleShape()..radius = 1.2);

  @override
  void update(double dt) {
    _elapsed += dt;
    if (_elapsed > random.nextDouble() * 3 + 1) {
      _elapsed = 0.0;
      world.raycast(this, position, _target);
    }
  }

  @override
  double reportFixture(Fixture f, Vector2 p, Vector2 n, double fr) {
    final ud = f.body.userData;
    if (ud is Maze || ud is Zombie && (p - position).length < 4) {
      final newAngle = angle + pi * 0.5;
      body.linearVelocity = Vector2(0, -1)
        ..scale(_speed)
        ..rotate(newAngle);
      body.setTransform(position, newAngle);
      return fr;
    }
    return 0;
  }
}

class Bullet extends BodyComponent with ContactCallbacks {
  Bullet(this.initalPosition, this.direction);

  final Vector2 initalPosition;
  final Vector2 direction;
  final _speed = 50.0;

  @override
  Body createBody() => world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          bullet: true,
          position: initalPosition,
          linearVelocity: direction.scaled(_speed),
          userData: this,
        ),
      )..createFixture(FixtureDef(CircleShape()..radius = 0.1, isSensor: true));

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

class Exit extends BodyComponent<Lost> with ContactCallbacks {
  Exit(this.initalPosition);
  final Vector2 initalPosition;

  @override
  Body createBody() {
    paint.color = Colors.blue;
    return world.createBody(
      BodyDef(position: initalPosition..scale(game.wallW), userData: this),
    )..createFixture(
        FixtureDef(
          PolygonShape()..setAsBoxXY(game.wallW * 0.25, game.wallW * 0.25),
          isSensor: true,
        ),
      );
  }

  @override
  void beginContact(Object other, Contact contact) {
    super.beginContact(other, contact);
    if (other is Player) {
      text.text = 'You escaped succesfully!';
    }
  }
}
