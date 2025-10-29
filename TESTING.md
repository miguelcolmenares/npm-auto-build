# 🧪 Testing NPM Auto Build Action Locally

Esta guía te muestra diferentes maneras de probar el GitHub Action localmente antes de publicarlo.

## ✅ Métodos de Testing Disponibles

### 1. 🐳 **Prueba con Docker (Recomendado)**

Este es el método más simple y directo:

```bash
# 1. Construir la imagen Docker
docker build -t npm-auto-build-test .

# 2. Crear un proyecto de prueba
mkdir test-project && cd test-project
npm init -y
echo '{"scripts": {"build": "mkdir -p dist && echo \"console.log('Hello');\" > dist/main.js"}}' > package.json

# 3. Ejecutar el action
docker run --rm \
  -v "$(pwd):/github/workspace" \
  -e INPUT_COMMAND="build" \
  -e INPUT_DIRECTORY="." \
  -e INPUT_BUILD_DIR="dist" \
  -e INPUT_COMMIT_MESSAGE="test: automated build" \
  -e INPUT_GITHUB_TOKEN="" \
  -e INPUT_GIT_USER_NAME="Test User" \
  -e INPUT_GIT_USER_EMAIL="test@example.com" \
  npm-auto-build-test
```

### 2. 🎯 **Prueba con Script Automatizado**

Usa el script `test-debug.sh` incluido en este repositorio:

```bash
# Dar permisos de ejecución
chmod +x test-debug.sh

# Ejecutar la prueba
./test-debug.sh
```

### 3. 🏃 **Prueba con Act (GitHub Actions local)**

Instala `act` para simular GitHub Actions completamente:

```bash
# Instalar act
brew install act  # En macOS
# o
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash  # En Linux

# Ejecutar en un repositorio con workflow
act push
```

### 4. 🔧 **Prueba Manual Paso a Paso**

Para debug detallado:

```bash
# 1. Crear proyecto de prueba
mkdir my-test-app && cd my-test-app
git init
npm init -y

# 2. Agregar script de build
echo '{
  "name": "test-app",
  "scripts": {
    "build": "mkdir -p dist && echo \"Built at: $(date)\" > dist/build-info.txt"
  }
}' > package.json

# 3. Commit inicial
git add . && git commit -m "Initial commit"

# 4. Ejecutar action
docker run --rm \
  -v "$(pwd):/github/workspace" \
  -e INPUT_COMMAND="build" \
  -e INPUT_BUILD_DIR="dist" \
  -e INPUT_COMMIT_MESSAGE="chore: update build" \
  -e INPUT_GITHUB_TOKEN="" \
  npm-auto-build-test
```

## 🔍 **Variables de Entorno para Testing**

El action acepta estas variables de entorno para configuración:

```bash
INPUT_COMMAND="build"                    # Script npm a ejecutar
INPUT_DIRECTORY="."                      # Directorio del proyecto  
INPUT_BUILD_DIR="dist"                   # Directorio de build
INPUT_COMMIT_MESSAGE="chore: build"      # Mensaje de commit
INPUT_GITHUB_TOKEN=""                    # Token (vacío para pruebas locales)
INPUT_GIT_USER_NAME="Test User"          # Nombre de usuario Git
INPUT_GIT_USER_EMAIL="test@example.com"  # Email Git
INPUT_NODE_VERSION="18"                  # Versión de Node.js
```

## 📋 **Checklist de Testing**

- [ ] ✅ Action construye correctamente con Docker
- [ ] 🔍 Detecta `package.json` correctamente
- [ ] 📦 Instala dependencias (npm/yarn)
- [ ] 🏗️ Ejecuta comando de build especificado
- [ ] 📁 Encuentra directorio de build (auto-detección)
- [ ] 🔧 Configura Git correctamente
- [ ] 🔍 Detecta cambios en archivos de build
- [ ] ✨ Hace commit solo cuando hay cambios
- [ ] 📝 Usa mensaje de commit personalizado
- [ ] 🚫 No falla si no hay cambios
- [ ] 🔍 Logging claro y útil

## 🐛 **Troubleshooting**

### Error: "no such file or directory"
```bash
# Reconstruir imagen sin cache
docker build --no-cache -t npm-auto-build-test .
```

### Error: "Build directory not found"
```bash
# Especificar directorio correcto
-e INPUT_BUILD_DIR="build"  # para React
-e INPUT_BUILD_DIR="public" # para Gatsby
-e INPUT_BUILD_DIR="lib"    # para librerías TS
```

### Error: "No changes detected"
Es normal si el build genera el mismo contenido. Para probar con cambios:
```bash
# Usar timestamp en el build
echo '{"scripts": {"build": "mkdir -p dist && echo \"Built: $(date)\" > dist/main.js"}}' > package.json
```

## 📊 **Resultados Esperados**

### ✅ **Ejecución Exitosa**
```
[INFO] Starting NPM Auto Build Action
[INFO] Found package.json, proceeding with build
[INFO] Installing dependencies...
[INFO] Running build command: npm run build
[INFO] Adding build files to Git...
[INFO] Committing changes...
[INFO] ✅ Build completed and committed successfully!
```

### ⚠️ **Sin Cambios (Normal)**
```
[INFO] No changes detected in build directory. Nothing to commit.
```

### ❌ **Error Común**
```
[ERROR] package.json not found in /github/workspace
[ERROR] Build script 'build' not found in package.json
```

## 🎯 **Casos de Prueba Sugeridos**

1. **Proyecto React**: `create-react-app` con `npm run build`
2. **Proyecto Vue**: Vue CLI con `npm run build`  
3. **Librería TypeScript**: Con build a `lib/` o `dist/`
4. **Monorepo**: Multiple packages con builds separados
5. **Proyecto con Yarn**: Verificar detección automática
6. **Build sin cambios**: Verificar que no hace commit innecesario

## 🚀 **Testing en CI/CD**

Para testing en tu propio CI/CD:

```yml
name: Test Action
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Test action
        uses: ./
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```