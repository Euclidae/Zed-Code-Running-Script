#!/bin/bash

# ===================================
# Enhanced Build Script for Zed Editor
# ===================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
log() {
    printf "${BLUE}[BUILD]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
    return 1
}

warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

info() {
    printf "${CYAN}[INFO]${NC} %s\n" "$1"
}

debug() {
    printf "${PURPLE}[DEBUG]${NC} %s\n" "$1"
}

# Enhanced dependency checking with version support
check_dependency() {
    local cmd=$1
    local package=$2
    local min_version=$3
    
    if ! command -v "$cmd" &> /dev/null; then
        warning "$cmd not found. You might need to install $package"
        return 1
    fi
    
    if [ -n "$min_version" ]; then
        local version=$($cmd --version 2>&1 | head -n1 | grep -oP '(\d+\.)+\d+' || echo "0.0.0")
        if ! printf '%s\n%s\n' "$min_version" "$version" | sort -V -C; then
            warning "$cmd version $version is lower than required version $min_version"
            return 1
        fi
    fi
    
    return 0
}

# Detect preferred C/C++ compiler
detect_compiler() {
    # Prefer clang if available
    if command -v clang++ &> /dev/null; then
        echo "clang++"
    elif command -v g++ &> /dev/null; then
        echo "g++"
    else
        error "No C++ compiler found. Please install clang++ or g++"
        return 1
    fi
}

# Function to check build system
check_build_system() {
    local dir="$1"
    
    if [ -f "$dir/CMakeLists.txt" ]; then
        echo "cmake"
    elif [ -f "$dir/Makefile" ] || [ -f "$dir/makefile" ]; then
        echo "make"
    elif [ -f "$dir/Cargo.toml" ]; then
        echo "cargo"
    elif [ -f "$dir/pyproject.toml" ]; then
        echo "poetry"
    elif [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
        echo "gradle"
    elif [ -f "$dir/pom.xml" ]; then
        echo "maven"
    elif [ -f "$dir/build.zig" ]; then
        echo "zig"
    elif [ -f "$dir/package.json" ]; then
        echo "npm"
    else
        echo "unknown"
    fi
}

# Function to recursively find all related source files
find_related_sources() {
    local main_file="$1"
    local dir=$(dirname "$main_file")
    local seen=()
    local queue=("$main_file")
    local all_files=()
    local system_includes=()
    local user_includes=()
    
    # Default compiler and language detection
    local compiler=$(detect_compiler)
    local is_cpp=0
    if [[ "${main_file}" =~ \.(cpp|cc|cxx|C|CPP)$ ]]; then
        is_cpp=1
    fi
    
    # Check for main files with standard names if not already specified
    if [[ ! "${main_file}" =~ main\.(c|cpp|cc|cxx)$ ]]; then
        for pattern in "main.cpp" "main.c" "main.cc" "main.cxx" "app.cpp" "app.c"; do
            if [[ -f "$dir/$pattern" ]]; then
                if [[ "$pattern" =~ \.cpp$ ]] || [[ "$pattern" =~ \.cc$ ]] || [[ "$pattern" =~ \.cxx$ ]]; then
                    is_cpp=1
                fi
                if [[ ! " ${all_files[@]} " =~ " $dir/$pattern " ]]; then
                    queue+=("$dir/$pattern")
                fi
            fi
        done
    fi
    
    # Process queue to find all related files
    while [ ${#queue[@]} -gt 0 ]; do
        current="${queue[0]}"
        queue=("${queue[@]:1}")
        
        [[ " ${seen[@]} " =~ " ${current} " ]] && continue
        seen+=("$current")
        
        # Extract filename for extension check to determine if it's a source file
        filename=$(basename "$current")
        case "$filename" in
            *.cpp|*.c|*.cc|*.cxx|*.C|*.CPP)
                # Add file if not already in list
                if [[ ! " ${all_files[@]} " =~ " ${current} " ]]; then
                    all_files+=("$current")
                fi
                ;;
            *.h|*.hpp|*.hxx|*.hh)
                # For header files, look for matching implementation files
                base_name="${filename%.*}"
                for ext in ".cpp" ".c" ".cc" ".cxx" ".C" ".CPP"; do
                    impl_file="$(dirname "$current")/${base_name}${ext}"
                    if [[ -f "$impl_file" ]] && [[ ! " ${seen[@]} " =~ " ${impl_file} " ]]; then
                        queue+=("$impl_file")
                    fi
                    
                    # Also search in src directory if it exists
                    if [[ -d "$(dirname "$current")/src" ]]; then
                        impl_file="$(dirname "$current")/src/${base_name}${ext}"
                        if [[ -f "$impl_file" ]] && [[ ! " ${seen[@]} " =~ " ${impl_file} " ]]; then
                            queue+=("$impl_file")
                        fi
                    fi
                done
                ;;
        esac
        
        # Parse file for includes if file exists and is readable
        if [ -f "$current" ] && [ -r "$current" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                # Remove comments and leading whitespace
                line=$(echo "$line" | sed -e 's/\/\/.*$//' -e 's/\/\*.*\*\///' -e 's/^[[:space:]]*//')
                
                # Check for includes
                if echo "$line" | grep -q "^#include"; then
                    if echo "$line" | grep -q "^#include *<.*>"; then
                        # System include
                        header=$(echo "$line" | sed 's/^#include *<\(.*\)>.*/\1/')
                        if [[ ! " ${system_includes[@]} " =~ " $header " ]]; then
                            system_includes+=("$header")
                        fi
                    else
                        # User include with quotes
                        header=$(echo "$line" | sed 's/^#include *"\(.*\)".*/\1/')
                        if [[ ! " ${user_includes[@]} " =~ " $header " ]]; then
                            user_includes+=("$header")
                            
                            # Search for the included file in various directories
                            found=0
                            for search_path in "$dir" "$dir/include" "$dir/src" "$dir/headers" "$dir/source" "$(dirname "$current")"; do
                                if [[ -f "$search_path/$header" ]]; then
                                    full_path="$search_path/$header"
                                    if [[ ! " ${queue[@]} " =~ " ${full_path} " ]]; then
                                        queue+=("$full_path")
                                        found=1
                                        break
                                    fi
                                fi
                            done
                            
                            # If not found in standard locations, try to find it recursively
                            if [ $found -eq 0 ]; then
                                while IFS= read -r -d '' found_file; do
                                    if [[ ! " ${queue[@]} " =~ " ${found_file} " ]]; then
                                        queue+=("$found_file")
                                    fi
                                done < <(find "$dir" -type f -name "$header" -print0 2>/dev/null)
                            fi
                        fi
                    fi
                fi
            done < "$current"
        else
            if [ -f "$current" ]; then
                warning "File $current exists but is not readable"
            else
                warning "File $current does not exist"
            fi
        fi
    done
    
    # Library detection for specific includes
    IMGUI_NEEDED=0
    SDL2_NEEDED=0
    SDL3_NEEDED=0
    SDL2_IMAGE_NEEDED=0
    SDL3_IMAGE_NEEDED=0
    SDL2_TTF_NEEDED=0
    SDL3_TTF_NEEDED=0
    SDL2_MIXER_NEEDED=0
    SDL3_MIXER_NEEDED=0
    OPENGL_NEEDED=0
    GLAD_NEEDED=0
    GLEW_NEEDED=0
    SFML_NEEDED=0
    RAYLIB_NEEDED=0
    ASSIMP_NEEDED=0
    FMOD_NEEDED=0
    SOIL_NEEDED=0
    GLFW_NEEDED=0
    ASIO_NEEDED=0
    VULKAN_NEEDED=0
    BOOST_NEEDED=0
    STB_NEEDED=0
    
    for include in "${system_includes[@]}"; do
        case "$include" in
            GL/*|OpenGL/*)
                OPENGL_NEEDED=1
                ;;
            glad.h|glad/glad.h)
                GLAD_NEEDED=1
                OPENGL_NEEDED=1
                ;;
            GL/glew.h)
                GLEW_NEEDED=1
                OPENGL_NEEDED=1
                ;;
            GLFW/*)
                GLFW_NEEDED=1
                ;;
            SDL3/SDL_image.h|SDL_image.h)
                SDL3_IMAGE_NEEDED=1
                SDL3_NEEDED=1
                ;;
            SDL2/SDL_image.h)
                SDL2_IMAGE_NEEDED=1
                SDL2_NEEDED=1
                ;;
            SDL3/SDL_ttf.h)
                SDL3_TTF_NEEDED=1
                SDL3_NEEDED=1
                ;;
            SDL2/SDL_ttf.h)
                SDL2_TTF_NEEDED=1
                SDL2_NEEDED=1
                ;;
            SDL3/SDL_mixer.h)
                SDL3_MIXER_NEEDED=1
                SDL3_NEEDED=1
                ;;
            SDL2/SDL_mixer.h)
                SDL2_MIXER_NEEDED=1
                SDL2_NEEDED=1
                ;;
            SDL3/*)
                SDL3_NEEDED=1
                ;;
            SDL2/*)
                SDL2_NEEDED=1
                ;;
            SFML/*)
                SFML_NEEDED=1
                ;;
            raylib.h)
                RAYLIB_NEEDED=1
                ;;
            imgui*)
                IMGUI_NEEDED=1
                ;;
            assimp/*)
                ASSIMP_NEEDED=1
                ;;
            fmod*.hpp|fmod.h)
                FMOD_NEEDED=1
                ;;
            SOIL*.h)
                SOIL_NEEDED=1
                ;;
            stb_*.h)
                STB_NEEDED=1
                ;;
            asio.hpp|asio/*)
                ASIO_NEEDED=1
                ;;
            vulkan/*)
                VULKAN_NEEDED=1
                ;;
            boost/*)
                BOOST_NEEDED=1
                ;;
        esac
    done
    
    # Final verification for main function existence
    has_main=0
    for file in "${all_files[@]}"; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            if grep -q -E '^[[:space:]]*int[[:space:]]+main\(.*\)' "$file"; then
                has_main=1
                break
            fi
        fi
    done
    
    if [ $has_main -eq 0 ]; then
        warning "No main function found in source files! Compilation might fail."
    fi
    
    # Print detected libraries
    log "Required libraries detected:"
    [ $IMGUI_NEEDED -eq 1 ] && echo "- ImGui"
    [ $SDL2_NEEDED -eq 1 ] && echo "- SDL2"
    [ $SDL3_NEEDED -eq 1 ] && echo "- SDL3"
    [ $SDL2_IMAGE_NEEDED -eq 1 ] && echo "- SDL2_image"
    [ $SDL3_IMAGE_NEEDED -eq 1 ] && echo "- SDL3_image"
    [ $SDL2_TTF_NEEDED -eq 1 ] && echo "- SDL2_ttf"
    [ $SDL3_TTF_NEEDED -eq 1 ] && echo "- SDL3_ttf"
    [ $SDL2_MIXER_NEEDED -eq 1 ] && echo "- SDL2_mixer"
    [ $SDL3_MIXER_NEEDED -eq 1 ] && echo "- SDL3_mixer"
    [ $OPENGL_NEEDED -eq 1 ] && echo "- OpenGL"
    [ $GLAD_NEEDED -eq 1 ] && echo "- GLAD"
    [ $GLEW_NEEDED -eq 1 ] && echo "- GLEW"
    [ $GLFW_NEEDED -eq 1 ] && echo "- GLFW"
    [ $SFML_NEEDED -eq 1 ] && echo "- SFML"
    [ $RAYLIB_NEEDED -eq 1 ] && echo "- Raylib"
    [ $ASSIMP_NEEDED -eq 1 ] && echo "- Assimp"
    [ $FMOD_NEEDED -eq 1 ] && echo "- FMOD"
    [ $SOIL_NEEDED -eq 1 ] && echo "- SOIL"
    [ $STB_NEEDED -eq 1 ] && echo "- STB"
    [ $ASIO_NEEDED -eq 1 ] && echo "- Asio"
    [ $VULKAN_NEEDED -eq 1 ] && echo "- Vulkan"
    [ $BOOST_NEEDED -eq 1 ] && echo "- Boost"
    
    # Return results
    echo "SOURCE_FILES=(${all_files[*]})"
    echo "COMPILER=$compiler"
    echo "IS_CPP=$is_cpp"
    echo "IMGUI_NEEDED=$IMGUI_NEEDED"
    echo "SDL2_NEEDED=$SDL2_NEEDED"
    echo "SDL3_NEEDED=$SDL3_NEEDED"
    echo "SDL2_IMAGE_NEEDED=$SDL2_IMAGE_NEEDED"
    echo "SDL3_IMAGE_NEEDED=$SDL3_IMAGE_NEEDED"
    echo "SDL2_TTF_NEEDED=$SDL2_TTF_NEEDED"
    echo "SDL3_TTF_NEEDED=$SDL3_TTF_NEEDED"
    echo "SDL2_MIXER_NEEDED=$SDL2_MIXER_NEEDED"
    echo "SDL3_MIXER_NEEDED=$SDL3_MIXER_NEEDED"
    echo "OPENGL_NEEDED=$OPENGL_NEEDED"
    echo "GLAD_NEEDED=$GLAD_NEEDED"
    echo "GLEW_NEEDED=$GLEW_NEEDED"
    echo "GLFW_NEEDED=$GLFW_NEEDED"
    echo "SFML_NEEDED=$SFML_NEEDED"
    echo "RAYLIB_NEEDED=$RAYLIB_NEEDED"
    echo "ASSIMP_NEEDED=$ASSIMP_NEEDED"
    echo "FMOD_NEEDED=$FMOD_NEEDED"
    echo "SOIL_NEEDED=$SOIL_NEEDED"
    echo "STB_NEEDED=$STB_NEEDED"
    echo "ASIO_NEEDED=$ASIO_NEEDED"
    echo "VULKAN_NEEDED=$VULKAN_NEEDED"
    echo "BOOST_NEEDED=$BOOST_NEEDED"
}

# Enhanced compilation with sanitizer support
compile_cpp() {
    local main_file="$1"
    local output_name="$2"
    local dir=$(dirname "$main_file")
    
    # Export variables from find_related_sources
    eval "$(find_related_sources "$main_file")"
    
    # Ensure we have compiler
    if [ -z "$COMPILER" ]; then
        COMPILER=$(detect_compiler)
    fi
    
    check_dependency "$COMPILER" "$COMPILER" || return 1
    
    # Set up include paths with common locations
    INCLUDE_PATHS="-I/usr/include -I/usr/local/include -I$dir -I$dir/include -I$dir/src"
    
    # Add library-specific include paths
    [ $SDL2_NEEDED -eq 1 ] && INCLUDE_PATHS="$INCLUDE_PATHS -I/usr/include/SDL2"
    [ $SDL3_NEEDED -eq 1 ] && INCLUDE_PATHS="$INCLUDE_PATHS -I/usr/include/SDL3"
    [ $OPENGL_NEEDED -eq 1 ] && INCLUDE_PATHS="$INCLUDE_PATHS -I/usr/include/glad"
    [ $VULKAN_NEEDED -eq 1 ] && INCLUDE_PATHS="$INCLUDE_PATHS -I/usr/include/vulkan"
    
    # Handle GLAD and GLEW separately - they shouldn't be used together
    GLAD_OBJ=""
    if [ $GLAD_NEEDED -eq 1 ]; then
        log "Compiling GLAD..."
        # First, check if the glad source exists in the project
        GLAD_SRC=""
        for search_path in "$dir/deps" "$dir/external" "$dir/third_party" "$dir/src" "/usr/src"; do
            if [ -f "$search_path/glad.c" ]; then
                GLAD_SRC="$search_path/glad.c"
                break
            fi
        done
        
        if [ -z "$GLAD_SRC" ]; then
            # Try to find it in common system locations
            GLAD_SRC="/usr/src/glad.c"
        fi
        
        if [ -f "$GLAD_SRC" ]; then
            $COMPILER -c "$GLAD_SRC" -I/usr/include/glad -o glad.o
            GLAD_OBJ="glad.o"
        else
            warning "GLAD source file not found. Linking might fail."
        fi
    fi
    
    # Detect C++ standard from files
    CPP_STANDARD="c++23"  # Default to C++23
    
    for file in "${SOURCE_FILES[@]}"; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            if grep -q "requires" "$file" || grep -q "concept" "$file"; then
                CPP_STANDARD="c++20"  # Use C++20 if concepts/requires are used
                break
            fi
            
            # Check for C++20 modules
            if grep -q "^[[:space:]]*import" "$file" || grep -q "^[[:space:]]*export[[:space:]]+module" "$file"; then
                CPP_STANDARD="c++20"
                break
            fi
        fi
    done
    
    # Check for C++17 features
    if [ "$CPP_STANDARD" = "c++23" ]; then
        for file in "${SOURCE_FILES[@]}"; do
            if [ -f "$file" ] && [ -r "$file" ]; then
                if grep -q "std::filesystem" "$file" || grep -q "std::optional" "$file" || grep -q "std::variant" "$file"; then
                    CPP_STANDARD="c++17"
                    break
                fi
            fi
        done
    fi
    
    # Determine if sanitizers are appropriate
    SANITIZER=""
    if [ "${ENABLE_SANITIZER:-0}" = "1" ]; then
        if [ "$COMPILER" = "clang++" ]; then
            SANITIZER="-fsanitize=address,undefined -fno-omit-frame-pointer"
        elif [ "$COMPILER" = "g++" ]; then
            SANITIZER="-fsanitize=address -fno-omit-frame-pointer"
        fi
    fi
    
    # Build compilation command with optimizations
    CMD="$COMPILER -std=$CPP_STANDARD"
    
    # Add optimization and warning flags
    if [ "${DEBUG:-0}" = "1" ]; then
        CMD="$CMD -g -O0 -Wall -Wextra -Wpedantic"
    else
        CMD="$CMD -O2 -Wall -Wextra"
    fi
    
    # Add sanitizer if enabled
    [ -n "$SANITIZER" ] && CMD="$CMD $SANITIZER"
    
    # Add source files
    for src in "${SOURCE_FILES[@]}"; do
        if [ -f "$src" ]; then
            CMD="$CMD \"$src\""
        fi
    done
    
    # Add GLAD object if needed
    [ -n "$GLAD_OBJ" ] && CMD="$CMD $GLAD_OBJ"
    
    # Add output name
    CMD="$CMD -o \"$output_name\" $INCLUDE_PATHS"
    
    # Add libraries in dependency order
    # SDL3 libraries
    [ $SDL3_NEEDED -eq 1 ] && CMD="$CMD -lSDL3"
    [ $SDL3_IMAGE_NEEDED -eq 1 ] && CMD="$CMD -lSDL3_image"
    [ $SDL3_TTF_NEEDED -eq 1 ] && CMD="$CMD -lSDL3_ttf"
    [ $SDL3_MIXER_NEEDED -eq 1 ] && CMD="$CMD -lSDL3_mixer"
    
    # SDL2 libraries
    [ $SDL2_NEEDED -eq 1 ] && CMD="$CMD -lSDL2 -lSDL2main"
    [ $SDL2_IMAGE_NEEDED -eq 1 ] && CMD="$CMD -lSDL2_image"
    [ $SDL2_TTF_NEEDED -eq 1 ] && CMD="$CMD -lSDL2_ttf"
    [ $SDL2_MIXER_NEEDED -eq 1 ] && CMD="$CMD -lSDL2_mixer"
    
    # Graphics libraries
    [ $OPENGL_NEEDED -eq 1 ] && CMD="$CMD -lGL"
    # Only add GLEW if GLAD isn't used
    [ $GLEW_NEEDED -eq 1 ] && [ $GLAD_NEEDED -ne 1 ] && CMD="$CMD -lGLEW"
    [ $VULKAN_NEEDED -eq 1 ] && CMD="$CMD -lvulkan"
    [ $GLFW_NEEDED -eq 1 ] && CMD="$CMD -lglfw"
    
    # Other libraries
    [ $SFML_NEEDED -eq 1 ] && CMD="$CMD -lsfml-graphics -lsfml-window -lsfml-system"
    [ $RAYLIB_NEEDED -eq 1 ] && CMD="$CMD -lraylib"
    [ $ASSIMP_NEEDED -eq 1 ] && CMD="$CMD -lassimp"
    [ $SOIL_NEEDED -eq 1 ] && CMD="$CMD -lSOIL"
    [ $FMOD_NEEDED -eq 1 ] && CMD="$CMD -L/usr/local/lib/fmod -lfmod"
    [ $BOOST_NEEDED -eq 1 ] && CMD="$CMD -lboost_system -lboost_filesystem"
    [ $ASIO_NEEDED -eq 1 ] && CMD="$CMD -lpthread"
    
    # Add common libraries and threading support
    CMD="$CMD -ldl -lpthread -lm"
    
    # Execute compilation with better error handling
    log "Executing: $CMD"
    if eval $CMD; then
        success "Compilation successful"
        return 0
    else
        error "Compilation failed"
        return 1
    fi
}

# Enhanced Python handling with data science support
handle_python() {
    local file="$1"
    local dir=$(dirname "$file")
    
    check_dependency "python3" "python3" "3.8.0" || return 1
    
    # Check for data science imports
    if grep -q "import \(pandas\|numpy\|matplotlib\|scipy\|sklearn\|tensorflow\|torch\|keras\)" "$file"; then
        log "Data science project detected"
        if [ ! -f "$dir/requirements.txt" ]; then
            warning "Creating requirements.txt with common data science packages"
            cat > "$dir/requirements.txt" << EOF
numpy>=1.20.0
pandas>=1.3.0
matplotlib>=3.4.0
scipy>=1.7.0
scikit-learn>=0.24.0
jupyter>=1.0.0
EOF
        fi
    fi
    
    # Poetry support
    if [ -f "$dir/pyproject.toml" ]; then
        log "Poetry project detected"
        if ! command -v poetry &> /dev/null; then
            warning "Poetry not found. Installing..."
            curl -sSL https://install.python-poetry.org | python3 -
        fi
        (cd "$dir" && poetry install && poetry run python "$file")
        return $?
    fi
    
    # Pipenv support
    if [ -f "$dir/Pipfile" ]; then
        log "Pipenv project detected"
        if ! command -v pipenv &> /dev/null; then
            warning "Pipenv not found. Installing..."
            pip3 install --user pipenv
        fi
        (cd "$dir" && pipenv install && pipenv run python "$file")
        return $?
    fi
    
    # Traditional requirements.txt
    if [ -f "$dir/requirements.txt" ]; then
        log "Python project with requirements.txt detected"
        if [ ! -d "$dir/venv" ]; then
            python3 -m venv "$dir/venv"
            source "$dir/venv/bin/activate"
            pip install -r "$dir/requirements.txt"
        else
            source "$dir/venv/bin/activate"
        fi
        
        # Check for Jupyter notebooks
        if [[ "$file" == *.ipynb ]]; then
            jupyter notebook "$file"
        else
            python3 "$file"
        fi
        
        local result=$?
        deactivate
        return $result
    fi
    
    # Handle Jupyter notebooks without venv
    if [[ "$file" == *.ipynb ]]; then
        if ! command -v jupyter &> /dev/null; then
            pip3 install --user jupyter
        fi
        jupyter notebook "$file"
    else
        python3 "$file"
    fi
}

# Enhanced web development support
handle_web() {
    local file="$1"
    local dir=$(dirname "$file")
    local browser="firefox"  # Change this to your preferred browser
    
    # Check for common browsers
    if command -v google-chrome &> /dev/null; then
        browser="google-chrome"
    elif command -v chromium &> /dev/null; then
        browser="chromium"
    elif command -v firefox &> /dev/null; then
        browser="firefox"
    fi
    
    # Handle different web file types
    case "${file##*.}" in
        html)
            # Check if it's a React project
            if [ -f "$dir/package.json" ] && grep -q '"react"' "$dir/package.json"; then
                log "React project detected"
                (cd "$dir" && [ ! -d "node_modules" ] && npm install)
                (cd "$dir" && npm start)
            else
                # Simple HTML file
                $browser "$file"
            fi
            ;;
        js)
            if [ -f "$dir/package.json" ]; then
                log "Node.js project detected"
                (cd "$dir" && [ ! -d "node_modules" ] && npm install)
                
                # Check for different frameworks
                if grep -q '"next"' "$dir/package.json"; then
                    log "Next.js project detected"
                    (cd "$dir" && npm run dev)
                elif grep -q '"vue"' "$dir/package.json"; then
                    log "Vue.js project detected"
                    (cd "$dir" && npm run serve)
                elif grep -q '"angular"' "$dir/package.json"; then
                    log "Angular project detected"
                    (cd "$dir" && ng serve)
                else
                    (cd "$dir" && npm start)
                fi
            else
                # Standalone JS file
                node "$file"
            fi
            ;;
        ts)
            if [ -f "$dir/package.json" ]; then
                log "TypeScript project detected"
                (cd "$dir" && [ ! -d "node_modules" ] && npm install)
                (cd "$dir" && npm start)
            else
                # Standalone TypeScript file
                if ! command -v ts-node &> /dev/null; then
                    npm install -g ts-node
                fi
                ts-node "$file"
            fi
            ;;
        css)
            if [ -f "$dir/index.html" ]; then
                $browser "$dir/index.html"
            else
                warning "No HTML file found to preview CSS"
            fi
            ;;
    esac
}

# Enhanced Rust project handling
handle_rust() {
    local file="$1"
    local dir=$(dirname "$file")
    
    check_dependency "rustc" "rust" "1.70.0" || return 1
    check_dependency "cargo" "cargo" || return 1
    
    if [ -f "$dir/Cargo.toml" ]; then
        log "Cargo project detected"
        (cd "$dir" && {
            # Check for custom configurations
            if [ -f ".cargo/config.toml" ]; then
                if grep -q "\[profile.release\]" "Cargo.toml"; then
                    log "Building with release profile..."
                    cargo build --release && cargo run --release
                else
                    cargo run
                fi
            else
                # Development build by default
                if grep -q "bevy" "Cargo.toml"; then
                    log "Bevy game engine detected"
                    # Enable fast compiles for Bevy
                    export RUSTFLAGS="-C target-cpu=native"
                    cargo run --features bevy/dynamic
                else
                    cargo run
                fi
            fi
        })
    else
        log "Compiling standalone Rust file"
        (cd "$dir" && rustc -O "$file" -o "${file%.*}" && ./"${file%.*}")
    fi
}



# Function to handle game engine specific setups
handle_game_engine() {
    local dir="$1"
    
    # Unity project detection
    if [ -f "$dir/Assets/Scripts" ] && [ -f "$dir/ProjectSettings/ProjectSettings.asset" ]; then
        log "Unity project detected"
        if command -v unity-editor &> /dev/null; then
            unity-editor -projectPath "$dir"
        else
            warning "Unity Editor not found in PATH"
        fi
        return
    fi
    
    # Unreal Engine project detection
    if [ -f "$dir/*.uproject" ]; then
        log "Unreal Engine project detected"
        if command -v UE4Editor &> /dev/null; then
            UE4Editor "$(find "$dir" -name "*.uproject" -type f)"
        else
            warning "Unreal Editor not found in PATH"
        fi
        return
    fi
    
    # Godot project detection
    if [ -f "$dir/project.godot" ]; then
        log "Godot project detected"
        if command -v godot &> /dev/null; then
            godot --path "$dir"
        else
            warning "Godot not found in PATH"
        fi
        return
    fi
}

# Function to handle database projects
handle_database() {
    local file="$1"
    local dir=$(dirname "$file")
    
    # PostgreSQL
    if [ -f "$dir/*.sql" ] && grep -q "postgresql\|postgres" "$file"; then
        if command -v psql &> /dev/null; then
            log "PostgreSQL script detected"
            psql -f "$file"
        else
            warning "PostgreSQL not installed"
        fi
    fi
    
    # MongoDB
    if [ -f "$dir/*.js" ] && grep -q "mongodb\|mongoose" "$file"; then
        if command -v mongo &> /dev/null; then
            log "MongoDB script detected"
            mongo "$file"
        else
            warning "MongoDB not installed"
        fi
    fi
}

# Main execution
main() {
    local full_path="$ZED_FILE"
    local filename_ext=$(basename "$full_path")
    local filename="${filename_ext%.*}"
    local extension="${filename_ext##*.}"
    local dir=$(dirname "$full_path")
    
    log "Processing $filename_ext"
    
    # Check for project-wide build systems first
    local build_system=$(check_build_system "$dir")
    case "$build_system" in
        "cmake")
            log "CMake project detected"
            mkdir -p "$dir/build" && cd "$dir/build"
            cmake .. && make -j$(nproc)
            if [ -f "$filename" ]; then
                ./"$filename"
            fi
            return
            ;;
        "make")
            log "Makefile project detected"
            make && ./"$filename"
            return
            ;;
        "cargo")
            handle_rust "$full_path"
            return
            ;;
        "poetry"|"pipenv")
            handle_python "$full_path"
            return
            ;;
    esac
    
    # Handle specific file types
    case "$extension" in
        c|cpp|cxx|cc)
            compile_cpp "$full_path" "$filename"
            if [ $? -eq 0 ]; then
                ./"$filename"
            fi
            ;;
        py|ipynb)
            handle_python "$full_path"
            ;;
        rs)
            handle_rust "$full_path"
            ;;
        html|js|ts|css)
            handle_web "$full_path"
            ;;
        java)
            handle_java "$full_path"
            ;;
        go)
            handle_go "$full_path"
            ;;
        sql)
            handle_database "$full_path"
            ;;
        *)
            error "Unsupported file type: .$extension"
            return 1
            ;;
    esac
}

# Execute main function with proper error handling
if [ -z "$ZED_FILE" ]; then
    error "No input file specified"
    exit 1
fi

main "$ZED_FILE"
exit $?
