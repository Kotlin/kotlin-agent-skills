# Kotlin Compiler Plugins for Maven

When using Kotlin with frameworks that require compiler plugins (Spring, serialization,
etc.), configure them inside the `kotlin-maven-plugin` block.

## Spring (all-open + no-arg)

Spring requires classes and certain members to be non-final. The `spring` compiler
plugin (built on `all-open`) handles this automatically.

```xml
<plugin>
    <groupId>org.jetbrains.kotlin</groupId>
    <artifactId>kotlin-maven-plugin</artifactId>
    <version>${kotlin.version}</version>
    <extensions>true</extensions>
    <configuration>
        <compilerPlugins>
            <plugin>spring</plugin>
        </compilerPlugins>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-allopen</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
    </dependencies>
</plugin>
```

The `spring` plugin automatically opens classes annotated with:
- `@Component`, `@Service`, `@Repository`, `@Controller`
- `@Configuration`
- `@Transactional`
- `@Async`
- `@Cacheable`

## JPA / no-arg

JPA entities require a no-argument constructor. The `jpa` compiler plugin (built on
`no-arg`) generates one automatically.

```xml
<plugin>
    <groupId>org.jetbrains.kotlin</groupId>
    <artifactId>kotlin-maven-plugin</artifactId>
    <version>${kotlin.version}</version>
    <extensions>true</extensions>
    <configuration>
        <compilerPlugins>
            <plugin>spring</plugin>
            <plugin>jpa</plugin>
        </compilerPlugins>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-allopen</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-noarg</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
    </dependencies>
</plugin>
```

The `jpa` plugin generates no-arg constructors for classes annotated with:
- `@Entity`
- `@Embeddable`
- `@MappedSuperclass`

## Kotlin Serialization

```xml
<plugin>
    <groupId>org.jetbrains.kotlin</groupId>
    <artifactId>kotlin-maven-plugin</artifactId>
    <version>${kotlin.version}</version>
    <extensions>true</extensions>
    <configuration>
        <compilerPlugins>
            <plugin>kotlinx-serialization</plugin>
        </compilerPlugins>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-serialization</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
    </dependencies>
</plugin>
```

Also add the runtime dependency:

```xml
<dependency>
    <groupId>org.jetbrains.kotlinx</groupId>
    <artifactId>kotlinx-serialization-json</artifactId>
    <version>1.8.1</version>
</dependency>
```

## Custom all-open Annotations

To open classes with custom annotations (not covered by the `spring` plugin):

```xml
<configuration>
    <compilerPlugins>
        <plugin>all-open</plugin>
    </compilerPlugins>
    <pluginOptions>
        <option>all-open:annotation=com.example.MyOpenAnnotation</option>
    </pluginOptions>
</configuration>
```

## Custom no-arg Annotations

To generate no-arg constructors for custom annotations:

```xml
<configuration>
    <compilerPlugins>
        <plugin>no-arg</plugin>
    </compilerPlugins>
    <pluginOptions>
        <option>no-arg:annotation=com.example.MyNoArgAnnotation</option>
        <!-- Optional: make the generated constructor callable from Kotlin code -->
        <option>no-arg:invokeInitializers=true</option>
    </pluginOptions>
</configuration>
```

## Combining Multiple Plugins

List all needed plugins in a single `<compilerPlugins>` block and all their
dependencies in the plugin's `<dependencies>`:

```xml
<plugin>
    <groupId>org.jetbrains.kotlin</groupId>
    <artifactId>kotlin-maven-plugin</artifactId>
    <version>${kotlin.version}</version>
    <extensions>true</extensions>
    <configuration>
        <compilerPlugins>
            <plugin>spring</plugin>
            <plugin>jpa</plugin>
            <plugin>kotlinx-serialization</plugin>
        </compilerPlugins>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-allopen</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-noarg</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
        <dependency>
            <groupId>org.jetbrains.kotlin</groupId>
            <artifactId>kotlin-maven-serialization</artifactId>
            <version>${kotlin.version}</version>
        </dependency>
    </dependencies>
</plugin>
```
