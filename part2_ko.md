# Part 2 - World's Simplest SQL Compiler and Virtual Machine

sqlite의 클론을 만들고 있다. sqlite의 "front-end"는 문자열을 구문 분석하고 바이트 코드라는 내부 표현을 출력하는 SQL 컴파일러이다.

이 바이트 코드는 가상 머신으로 전달되어 가상 머신을 실행합니다.

![sqlite arch2](https://www.sqlite.org/images/arch2.gif)

이렇게 두 단계로 나누면 몇 가지 장점이 있다.:
- 각 부분의 복잡도 감소한다. ( 예를 들어, 가상머신은 문법 에러에 대해 고민하지 않는다. )
- 일반적인 쿼리를 한 번 컴파일하고 성능 향상을 위해 바이트 코드를 캐싱 할 수 있다.

이것을 염두에 두고, `main` 함수를 리펙토링하고 두 개의 키워드를 제안한다.

```diff
 int main(int argc, char* argv[]) {
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
     read_input(input_buffer);

-    if (strcmp(input_buffer->buffer, ".exit") == 0) {
-      exit(EXIT_SUCCESS);
-    } else {
-      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
+    if (input_buffer->buffer[0] == '.') {
+      switch (do_meta_command(input_buffer)) {
+        case (META_COMMAND_SUCCESS):
+          continue;
+        case (META_COMMAND_UNRECOGNIZED_COMMAND):
+          printf("Unrecognized command '%s'\n", input_buffer->buffer);
+          continue;
+      }
     }
+
+    Statement statement;
+    switch (prepare_statement(input_buffer, &statement)) {
+      case (PREPARE_SUCCESS):
+        break;
+      case (PREPARE_UNRECOGNIZED_STATEMENT):
+        printf("Unrecognized keyword at start of '%s'.\n",
+               input_buffer->buffer);
+        continue;
+    }
+
+    execute_statement(&statement);
+    printf("Executed.\n");
   }
 }
```
`.exit` 처럼 Non-SQL 명령어는 "meta-commands" 라고 불린다. "meta-commands"는 "."으로 시작하기 때문에 이를 검사하고 별도의 함수로 처리한다. 

다음으로, 입력 행을 내부 표현 명령어로 변환하는 과정을 추가한다. 이것은 sqlite front-end 의 해킹 버전이다.

마지막으로 `prepated statement`를 `execute_statement`에 전달한다. 이 함수는 결국 가상머신이 될 것이다.

새로운 함수 중 두 개는 성공 또는 실패를 나타내는 enum을 반환한다.

```c
enum MetaCommandResult_t {
  META_COMMAND_SUCCESS,
  META_COMMAND_UNRECOGNIZED_COMMAND
};
typedef enum MetaCommandResult_t MetaCommandResult;

enum PrepareResult_t { PREPARE_SUCCESS, PREPARE_UNRECOGNIZED_STATEMENT };
typedef enum PrepareResult_t PrepareResult;
```

"Unrecognized statement"? 이는 약간 예외처럼 보인다. 하지만  [exceptions are bad](https://www.youtube.com/watch?v=EVhCUSgNbzo) ( C에서는 예외를 지원하지 않음 ) 이기 때문에 실용적인 곳에서는 열거(enum)형 결과 코드를 사용하고 있다. C 컴파일러는 switch 문이 열거 형 멤버를 처리하지 못한다면 불평 할 것이므로 함수의 모든 결과를 처리 할 수 ​​있다고 확신 할 수 있다.

`do_meta_command`는 더 많은 명령을 위해 남겨둔 기존 기능에 대한 wrapper 일 뿐이다.:

```c
MetaCommandResult do_meta_command(InputBuffer* input_buffer) {
  if (strcmp(input_buffer->buffer, ".exit") == 0) {
    exit(EXIT_SUCCESS);
  } else {
    return META_COMMAND_UNRECOGNIZED_COMMAND;
  }
}
```

"prepared statement"에는 현재 가능한 두 가지 값을 가진 enum이 들어 있다. 명령문에 매개 변수를 허용 할 때 더 많은 데이터가 포함된다.

```c
enum StatementType_t { STATEMENT_INSERT, STATEMENT_SELECT };
typedef enum StatementType_t StatementType;

struct Statement_t {
  StatementType type;
};
typedef struct Statement_t Statement;
```

구현할 `prepare_statement` ( "SQL Compliter" ) 는 SQL을 바로 이해하지 않는다. 사실, 오직 두 단어만 이해한다.
```c
PrepareResult prepare_statement(InputBuffer* input_buffer,
                                Statement* statement) {
  if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
    statement->type = STATEMENT_INSERT;
    return PREPARE_SUCCESS;
  }
  if (strcmp(input_buffer->buffer, "select") == 0) {
    statement->type = STATEMENT_SELECT;
    return PREPARE_SUCCESS;
  }

  return PREPARE_UNRECOGNIZED_STATEMENT;
}
```

"insert" 키워드 뒤에 데이터가 올 것이므로 "insert"에 `strncmp`를 사용합니다. (e.g. `insert 1 cstack foo@bar.com`)

마지막으로 `execute_statement`은 몇 개의 스텁이 있다.:
```c
void execute_statement(Statement* statement) {
  switch (statement->type) {
    case (STATEMENT_INSERT):
      printf("This is where we would do an insert.\n");
      break;
    case (STATEMENT_SELECT):
      printf("This is where we would do a select.\n");
      break;
  }
}
```


아직 잘못 될 수 있는 오류가 없으므로 오류 코드가 반환되지 않는다.

리펙토링으로 두 새로운 키워드를 인식한다!
```command-line
~ ./db
db > insert foo bar
This is where we would do an insert.
Executed.
db > delete foo
Unrecognized keyword at start of 'delete foo'.
db > select
This is where we would do a select.
Executed.
db > .tables
Unrecognized command '.tables'
db > .exit
~
```

데이버베이스의 뼈대는 모양을 갖추는 중이다. 데이터를 저장하면 좋지 않을까? 다음 단계에서는 `insert`와`select`를 구현하여 효율 최악의 데이터 저장소를 만든다. 
변경 부분은 다음과 같다.

```diff
@@ -10,6 +10,23 @@ struct InputBuffer_t {
 };
 typedef struct InputBuffer_t InputBuffer;
 
+enum MetaCommandResult_t {
+  META_COMMAND_SUCCESS,
+  META_COMMAND_UNRECOGNIZED_COMMAND
+};
+typedef enum MetaCommandResult_t MetaCommandResult;
+
+enum PrepareResult_t { PREPARE_SUCCESS, PREPARE_UNRECOGNIZED_STATEMENT };
+typedef enum PrepareResult_t PrepareResult;
+
+enum StatementType_t { STATEMENT_INSERT, STATEMENT_SELECT };
+typedef enum StatementType_t StatementType;
+
+struct Statement_t {
+  StatementType type;
+};
+typedef struct Statement_t Statement;
+
 InputBuffer* new_input_buffer() {
   InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
   input_buffer->buffer = NULL;
@@ -35,16 +52,66 @@ void read_input(InputBuffer* input_buffer) {
   input_buffer->buffer[bytes_read - 1] = 0;
 }
 
+MetaCommandResult do_meta_command(InputBuffer* input_buffer) {
+  if (strcmp(input_buffer->buffer, ".exit") == 0) {
+    exit(EXIT_SUCCESS);
+  } else {
+    return META_COMMAND_UNRECOGNIZED_COMMAND;
+  }
+}
+
+PrepareResult prepare_statement(InputBuffer* input_buffer,
+                                Statement* statement) {
+  if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
+    statement->type = STATEMENT_INSERT;
+    return PREPARE_SUCCESS;
+  }
+  if (strcmp(input_buffer->buffer, "select") == 0) {
+    statement->type = STATEMENT_SELECT;
+    return PREPARE_SUCCESS;
+  }
+
+  return PREPARE_UNRECOGNIZED_STATEMENT;
+}
+
+void execute_statement(Statement* statement) {
+  switch (statement->type) {
+    case (STATEMENT_INSERT):
+      printf("This is where we would do an insert.\n");
+      break;
+    case (STATEMENT_SELECT):
+      printf("This is where we would do a select.\n");
+      break;
+  }
+}
+
 int main(int argc, char* argv[]) {
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
     read_input(input_buffer);
 
-    if (strcmp(input_buffer->buffer, ".exit") == 0) {
-      exit(EXIT_SUCCESS);
-    } else {
-      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
+    if (input_buffer->buffer[0] == '.') {
+      switch (do_meta_command(input_buffer)) {
+        case (META_COMMAND_SUCCESS):
+          continue;
+        case (META_COMMAND_UNRECOGNIZED_COMMAND):
+          printf("Unrecognized command '%s'\n", input_buffer->buffer);
+          continue;
+      }
     }
+
+    Statement statement;
+    switch (prepare_statement(input_buffer, &statement)) {
+      case (PREPARE_SUCCESS):
+        break;
+      case (PREPARE_UNRECOGNIZED_STATEMENT):
+        printf("Unrecognized keyword at start of '%s'.\n",
+               input_buffer->buffer);
+        continue;
+    }
+
+    execute_statement(&statement);
+    printf("Executed.\n");
   }
 }
```