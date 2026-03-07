/**
 * 3D terrain version:
 * - 600x600 P3D
 * - lower-angle corner camera
 * - true ground depth via x/z heightfield grid
 * - random grey terrain cells
 * - terrain turns red while colliding, reverts after
 * - mouse press adds upward throw impulse + slight random lateral push
 */

Orb orb;

PVector gravity = new PVector(0, 0.1, 0);

int cols = 22;
int rows = 22;

float worldW = 600;
float worldH = 600;
float worldD = 600;

float cellW;
float cellD;

float[][] heights;
GroundCell[][] cells;

void setup() {
  size(600, 600, P3D);
  smooth(8);

  cellW = worldW / (cols - 1.0);
  cellD = worldD / (rows - 1.0);

  generateTerrain();

  orb = new Orb(90, 120, 90, 12);
}

void draw() {
  background(10);

  setSceneCamera();
  lights();

  clearCollisionFlags();

  orb.move();
  orb.checkBounds();
  orb.checkTerrainCollision();

  drawTerrain();
  orb.display();
  
  if(keyPressed) {
    float fuck = 2.0;
    
    orb.velocity.y = -0.01;
    
    if(key == 'w') orb.velocity.x = fuck;
    if(key == 's') orb.velocity.x = -fuck;
    if(key == 'a') orb.velocity.z = -fuck;
    if(key == 'd') orb.velocity.z = fuck;
    if(key == ' ') orb.velocity.y = -2.5;
    
    key = ']';
  }
}

void mousePressed() {
  orb.kickUp();
}

void setSceneCamera() {
  // lower than before, roughly same distance from scene
  float cx = -150;
  float cy = -110;
  float cz = -150;

  float tx = worldW * 0.5;
  float ty = worldH * 0.70;
  float tz = worldD * 0.5;

  camera(cx, cy, cz, tx, ty, tz, 0, 1, 0);
}

void generateTerrain() {
  heights = new float[cols][rows];
  cells   = new GroundCell[cols - 1][rows - 1];

  noiseDetail(4, 0.5);

  float nScale = 0.16;
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      float nx = i * nScale;
      float nz = j * nScale;

      // broad rolling shape, biased toward the lower half of the screen
      float h = map(noise(nx, nz), 0, 1, worldH - 210, worldH - 40);
      heights[i][j] = h;
    }
  }

  for (int i = 0; i < cols - 1; i++) {
    for (int j = 0; j < rows - 1; j++) {
      float baseGrey;
      if ((i + j) % 2 == 0) baseGrey = random(80, 125);
      else                  baseGrey = random(135, 185);

      cells[i][j] = new GroundCell(i, j, baseGrey);
    }
  }
}

void clearCollisionFlags() {
  for (int i = 0; i < cols - 1; i++) {
    for (int j = 0; j < rows - 1; j++) {
      cells[i][j].colliding = false;
    }
  }
}

void drawTerrain() {
  for (int i = 0; i < cols - 1; i++) {
    for (int j = 0; j < rows - 1; j++) {
      cells[i][j].display();
    }
  }
}

float terrainHeightAt(float x, float z) {
  x = constrain(x, 0, worldW - 0.001);
  z = constrain(z, 0, worldD - 0.001);

  int i = constrain(floor(x / cellW), 0, cols - 2);
  int j = constrain(floor(z / cellD), 0, rows - 2);

  float x0 = i * cellW;
  float z0 = j * cellD;

  float u = (x - x0) / cellW;
  float v = (z - z0) / cellD;

  float h00 = heights[i][j];
  float h10 = heights[i + 1][j];
  float h01 = heights[i][j + 1];
  float h11 = heights[i + 1][j + 1];

  // bilinear interpolation over the cell
  float h0 = lerp(h00, h10, u);
  float h1 = lerp(h01, h11, u);
  return lerp(h0, h1, v);
}

PVector terrainNormalAt(float x, float z) {
  float epsX = cellW * 0.35;
  float epsZ = cellD * 0.35;

  float xL = max(0, x - epsX);
  float xR = min(worldW, x + epsX);
  float zD = max(0, z - epsZ);
  float zU = min(worldD, z + epsZ);

  float hL = terrainHeightAt(xL, z);
  float hR = terrainHeightAt(xR, z);
  float hD = terrainHeightAt(x, zD);
  float hU = terrainHeightAt(x, zU);

  PVector tx = new PVector(xR - xL, hR - hL, 0);
  PVector tz = new PVector(0, hU - hD, zU - zD);

  PVector n = tx.cross(tz);
  n.normalize();

  // make sure it points upward
  if (n.y > 0) n.mult(-1);

  return n;
}

class GroundCell {
  int i, j;
  float baseGrey;
  boolean colliding = false;

  GroundCell(int i, int j, float baseGrey) {
    this.i = i;
    this.j = j;
    this.baseGrey = baseGrey;
  }

  void display() {
    float x0 = i * cellW;
    float x1 = (i + 1) * cellW;
    float z0 = j * cellD;
    float z1 = (j + 1) * cellD;

    float h00 = heights[i][j];
    float h10 = heights[i + 1][j];
    float h11 = heights[i + 1][j + 1];
    float h01 = heights[i][j + 1];

    pushStyle();
    noStroke();

    if (colliding) fill(220, 40, 40);
    else fill(baseGrey);

    // top face
    beginShape(QUADS);
    vertex(x0, h00, z0);
    vertex(x1, h10, z0);
    vertex(x1, h11, z1);
    vertex(x0, h01, z1);
    endShape();

    // front edge wall at z0
    if (colliding) fill(180, 30, 30);
    else fill(max(0, baseGrey - 18));
    beginShape(QUADS);
    vertex(x0, h00, z0);
    vertex(x1, h10, z0);
    vertex(x1, worldH, z0);
    vertex(x0, worldH, z0);
    endShape();

    // left edge wall at x0
    if (colliding) fill(160, 22, 22);
    else fill(max(0, baseGrey - 34));
    beginShape(QUADS);
    vertex(x0, h00, z0);
    vertex(x0, h01, z1);
    vertex(x0, worldH, z1);
    vertex(x0, worldH, z0);
    endShape();

    popStyle();
  }
}

class Orb {
  PVector position;
  PVector velocity;
  float r;
  float damping = 0.5;
  float friction = 0.01;

  Orb(float x, float y, float z, float r_) {
    position = new PVector(x, y, z);
    velocity = new PVector(1.4, 0, 1.0);
    r = r_;
  }

  void move() {
    velocity.add(gravity);
    position.add(velocity);
  }

  void kickUp() {
    // upward = negative y in Processing's 3D coordinates
    velocity.y = random(-6.5, -4.8);

    // slight random lateral push so it gets thrown around
    velocity.x += random(-1.6, 1.6);
    velocity.z += random(-1.6, 1.6);
  }

  void display() {
    pushMatrix();
    translate(position.x, position.y, position.z);
    noStroke();
    fill(215);
    sphereDetail(20);
    sphere(r);
    popMatrix();
  }

  void checkBounds() {
    if (position.x < r) {
      position.x = r;
      velocity.x *= -damping;
    } else if (position.x > worldW - r) {
      position.x = worldW - r;
      velocity.x *= -damping;
    }

    if (position.z < r) {
      position.z = r;
      velocity.z *= -damping;
    } else if (position.z > worldD - r) {
      position.z = worldD - r;
      velocity.z *= -damping;
    }

    if (position.y < r) {
      position.y = r;
      velocity.y *= -damping;
    }
  }

  void checkTerrainCollision() {
    float groundY = terrainHeightAt(position.x, position.z);
    float bottomY = position.y + r;

    // contact only when sphere bottom reaches terrain and moving into it
    if (bottomY >= groundY && velocity.y >= -0.2) {
      PVector n = terrainNormalAt(position.x, position.z);

      // project sphere center to sit exactly one radius above terrain along world up
      position.y = groundY - r;

      // reflect velocity about terrain normal
      float vn = velocity.dot(n);

      // only respond if moving into the surface
      if (vn < 0) {
        PVector reflected = PVector.sub(velocity, PVector.mult(n, 2.0 * vn));
        velocity.set(reflected);
        velocity.mult(damping);
      }

      // tangential damping to reduce chatter
      velocity.x *= friction;
      velocity.z *= friction;

      markCollidingCell(position.x, position.z);
    }
  }

  void markCollidingCell(float x, float z) {
    int i = constrain(floor(x / cellW), 0, cols - 2);
    int j = constrain(floor(z / cellD), 0, rows - 2);
    cells[i][j].colliding = true;

    // mark neighbors too so the red patch reads as area contact, not a single tile
    if (i > 0)         cells[i - 1][j].colliding = true;
    if (i < cols - 2)  cells[i + 1][j].colliding = true;
    if (j > 0)         cells[i][j - 1].colliding = true;
    if (j < rows - 2)  cells[i][j + 1].colliding = true;
  }
}
