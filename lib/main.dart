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
void main() => runApp(const GameWidget.controlled(gameFactory: Lost.new));

class Lost extends Forge2DGame
    with HasKeyboardHandlerComponents, MouseMovementDetector, TapCallbacks {
  Lost() : super(cameraComponent: cam);

  @override
  Color backgroundColor() => const Color.fromARGB(255, 38, 62, 50);

  double get zoom => camera.viewfinder.zoom;
  double get wallWidth => 80 / zoom;
  double get wallThickness => 6 / zoom;
  double get wallSize => 10 * wallWidth;
  Vector2 get virtualSize => camera.viewport.virtualSize * 0.5 / zoom;

  final maze = Maze(10);
  final player = Player();

  @override
  Future<void> onLoad() async {
    world = Forge2DWorld(children: [maze, player], gravity: Vector2.zero());
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
    if (player.isMounted) {
      player.body.setTransform(
        player.body.position,
        (screenToWorld(info.eventPosition.global) - player.position)
            .screenAngle(),
      );
    }
  }

  @override
  void onTapDown(TapDownEvent event) => player.shoot();
}

enum PlayerAnimationState { walking, shooting }

class Player extends BodyComponent<Lost> with KeyboardHandler {
  final _moveSpeed = 1000.0;
  final _moveDirection = Vector2.zero();
  late final SpriteAnimationGroupComponent<PlayerAnimationState> _animation;

  @override
  Future<void> onLoad() async {
    super.onLoad();

    final spriteSheet = SpriteSheet.fromColumnsAndRows(
      image: await game.images.load('soldier-walking.png'),
      columns: 17,
      rows: 1,
    );

    final spriteSheet2 = SpriteSheet.fromColumnsAndRows(
      image: await game.images.load('soldier-shooting-fixed.png'),
      columns: 17,
      rows: 1,
    );

    _animation = SpriteAnimationGroupComponent<PlayerAnimationState>(
      animations: {
        PlayerAnimationState.walking:
            spriteSheet.createAnimation(row: 0, stepTime: 0.1),
        PlayerAnimationState.shooting:
            spriteSheet2.createAnimation(row: 0, stepTime: 0.08, loop: false),
      },
      size: Vector2.all(5),
      current: PlayerAnimationState.walking,
      anchor: Anchor.center,
    );
    await add(_animation);

    final shootTicker =
        _animation.animationTickers![PlayerAnimationState.shooting]!;
    shootTicker.onComplete = () {
      shootTicker.reset();
      _animation.current = PlayerAnimationState.walking;
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
    if (_animation.current == PlayerAnimationState.walking) {
      _animation.animationTicker!.paused = _moveDirection.isZero();
    } else {
      _moveDirection.setAll(0);
    }
    body.linearVelocity = _moveDirection * _moveSpeed * dt;
  }

  @override
  bool onKeyEvent(RawKeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _moveDirection.setAll(0);
    _moveDirection.x += keysPressed.contains(LogicalKeyboardKey.keyA) ? -1 : 0;
    _moveDirection.x += keysPressed.contains(LogicalKeyboardKey.keyD) ? 1 : 0;
    _moveDirection.y += keysPressed.contains(LogicalKeyboardKey.keyW) ? -1 : 0;
    _moveDirection.y += keysPressed.contains(LogicalKeyboardKey.keyS) ? 1 : 0;
    _moveDirection.normalize();
    return super.onKeyEvent(event, keysPressed);
  }

  void shoot() => _animation.current = PlayerAnimationState.shooting;
}

class Maze extends BodyComponent<Lost> {
  Maze(this.size) : maze = generate(width: size, height: size, seed: 5);
  final int size;
  final List<List<Cell>> maze;

  @override
  Body createBody() {
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
        if (i > 3 && j > 3 && random.nextBool() && random.nextBool()) {
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

class Zombie extends BodyComponent<Lost> {
  Zombie(this.initalPosition);
  Vector2 initalPosition;

  @override
  Future<void> onLoad() async {
    super.onLoad();

    final image = await game.images.load('zombie-walking.png');
    final spriteSheet =
        SpriteSheet.fromColumnsAndRows(image: image, columns: 11, rows: 1);
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
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: initalPosition,
        userData: this,
        angle: pi * random.nextDouble(),
      ),
    );
    return body..createFixtureFromShape(CircleShape()..radius = 1);
  }
}
