# Part 3 - An In-Memory, Append-Only, Single-Table Database

우리는 데이터베이스에 많은 한계를 두어 작게 시작할 것이다. 현재는 이러하다.:

- 두 가지 동작만 지원: 행 삽입과 모든 행 출력
- 메모리 상에만 배치 ( 디스크에 저장 안함 )
- hard-code 테이블은 한개만

hard-code 된 테이블은 사용자를 저장하고 다음과 같이 보입니다 :

| column   | type         |
|----------|--------------|
| id       | integer      |
| username | varchar(32)  |
| email    | varchar(255) |

단순한 스키마이지만 다양한 데이터 타입과 여러 데이터 크기를 지원 해야 한다.

`insert` 문은 다음처럼 실행할 것이다.

```
insert 1 cstack foo@bar.com
```

즉, 인수를 파싱하기 위해 `prepare_statement` 함수를 업그레이드 해야 한다.

```diff
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
     statement->type = STATEMENT_INSERT;
+    int args_assigned = sscanf(
+        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
+        statement->row_to_insert.username, statement->row_to_insert.email);
+    if (args_assigned < 3) {
+      return PREPARE_SYNTAX_ERROR;
+    }
     return PREPARE_SUCCESS;
   }
   if (strcmp(input_buffer->buffer, "select") == 0) {
```

구문 분석 된 인수를 명령문 객체의 새로운 `Row` 데이터 구조에 저장한다.

```diff
+const uint32_t COLUMN_USERNAME_SIZE = 32;
+const uint32_t COLUMN_EMAIL_SIZE = 255;
+struct Row_t {
+  uint32_t id;
+  char username[COLUMN_USERNAME_SIZE];
+  char email[COLUMN_EMAIL_SIZE];
+};
+typedef struct Row_t Row;
+
 struct Statement_t {
   StatementType type;
+  Row row_to_insert;  // only used by insert statement
 };
 typedef struct Statement_t Statement;
```


이제 우리는 테이블을 나타내는 데이터 구조로 구현 해야 한다. SQLite는 빠른 탐색, 삽입과 삭제를 위해 B-tree 이용한다. 
그러나 우리는 더 간단한 것으로 시작할 것이다 : 배열 Array.

데이터베이스가 필요한 공간을 미리 알 방법이 없으므로 동적으로 메모리를 할당 해야 한다. 하지만 행 당 여분의 메모리를 할당하는 것은 한 노드에서 다른 노드로 포인터를 저장하기 위해 많은 오버헤드가 있다.
또한 데이터 구조를 파일로 저장하는 것을 더 어렵게 만든다. 이에 대한 대안이다.:

- 페이지라 불리는 메모리 블록에 행을 저장한다.
- 각 페이지는 적합한 만큼의 많은 행을 저장한다.
- 행은 각 페이지와 함께 간단한 표현으로 직렬화된다.
- 페이지들은 오직 필요에 따라 할당된다.
- 페이지에 대한 고정 크기의 포인터 배열을 유지하여 인덱스 'i`의 행을 일정 시간에 찾을 수 있다.

먼저, 직렬화 및 역직렬화는 다음과 같다.:
```diff
+const uint32_t ID_SIZE = sizeof(((Row*)0)->id);
+const uint32_t USERNAME_SIZE = sizeof(((Row*)0)->username);
+const uint32_t EMAIL_SIZE = sizeof(((Row*)0)->email);
+const uint32_t ID_OFFSET = 0;
+const uint32_t USERNAME_OFFSET = ID_OFFSET + ID_SIZE;
+const uint32_t EMAIL_OFFSET = USERNAME_OFFSET + USERNAME_SIZE;
+const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
```
```diff
+void serialize_row(Row* source, void* destination) {
+  memcpy(destination + ID_OFFSET, &(source->id), ID_SIZE);
+  memcpy(destination + USERNAME_OFFSET, &(source->username), USERNAME_SIZE);
+  memcpy(destination + EMAIL_OFFSET, &(source->email), EMAIL_SIZE);
+}
+
+void deserialize_row(void* source, Row* destination) {
+  memcpy(&(destination->id), source + ID_OFFSET, ID_SIZE);
+  memcpy(&(destination->username), source + USERNAME_OFFSET, USERNAME_SIZE);
+  memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
+}
```


그 다음, 행 페이지를 가리키고 그 행 수를 추적하는 테이블 구조 :
```diff
+const uint32_t PAGE_SIZE = 4096;
+const uint32_t TABLE_MAX_PAGES = 100;
+const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
+const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
+
+struct Table_t {
+  void* pages[TABLE_MAX_PAGES];
+  uint32_t num_rows;
+};
+typedef struct Table_t Table;
```

그리고 메모리에서 특정 행이 어디로 가야 하는지를 찾는 법 :
```diff
+void* row_slot(Table* table, uint32_t row_num) {
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void* page = table->pages[page_num];
+  if (!page) {
+    // Allocate memory only when we try to access page
+    page = table->pages[page_num] = malloc(PAGE_SIZE);
+  }
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
```

테이블 구조에서 `execute_statement`를 read/write 가 가능하다.:
```diff
-void execute_statement(Statement* statement) {
+ExecuteResult execute_insert(Statement* statement, Table* table) {
+  if (table->num_rows >= TABLE_MAX_ROWS) {
+    return EXECUTE_TABLE_FULL;
+  }
+
+  Row* row_to_insert = &(statement->row_to_insert);
+
+  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  table->num_rows += 1;
+
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_select(Statement* statement, Table* table) {
+  Row row;
+  for (uint32_t i = 0; i < table->num_rows; i++) {
+    deserialize_row(row_slot(table, i), &row);
+    print_row(&row);
+  }
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_statement(Statement* statement, Table* table) {
   switch (statement->type) {
     case (STATEMENT_INSERT):
-      printf("This is where we would do an insert.\n");
-      break;
+      return execute_insert(statement, table);
     case (STATEMENT_SELECT):
-      printf("This is where we would do a select.\n");
-      break;
+      return execute_select(statement, table);
   }
 }
```

마지막으로 테이블 초기화와 많은 에러 처리를 해야 한다.:

```diff
+ Table* new_table() {
+  Table* table = malloc(sizeof(Table));
+  table->num_rows = 0;
+
+  return table;
+}
```
```diff
 int main(int argc, char* argv[]) {
+  Table* table = new_table();
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
@@ -105,13 +203,22 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_SYNTAX_ERROR):
+        printf("Syntax error. Could not parse statement.\n");
+        continue;
       case (PREPARE_UNRECOGNIZED_STATEMENT):
         printf("Unrecognized keyword at start of '%s'.\n",
                input_buffer->buffer);
         continue;
     }

-    execute_statement(&statement);
-    printf("Executed.\n");
+    switch (execute_statement(&statement, table)) {
+      case (PREPARE_SUCCESS):
+        printf("Executed.\n");
+        break;
+      case (EXECUTE_TABLE_FULL):
+        printf("Error: Table full.\n");
+        break;
+    }
   }
 }
 ```

이러한 변경으로 우리는 실제로 데이터베이스에 데이터를 저장할 수 있다!
 ```command-line
~ ./db
db > insert 1 cstack foo@bar.com
Executed.
db > insert 2 bob bob@example.com
Executed.
db > select
(1, cstack, foo@bar.com)
(2, bob, bob@example.com)
Executed.
db > insert foo bar 1
Syntax error. Could not parse statement.
db > .exit
~
```

몇 가지 이유로 몇 가지 테스트를 작성하는 것이 좋다.
- 우리는 테이블을 저장하는 데이터 구조를 극적으로 바꿀 계획이며, 테스트는 회귀를 초래할 것이다.
- 수동으로 테스트하지 않은 두 가지 경우가 있다. (e.g. 테이블 채우기)

Now would be a great time to write some tests, for a couple reasons:
- We're planning to dramatically change the data structure storing our table, and tests would catch regressions.
- There are a couple edge cases we haven't tested manually (e.g. filling up the table)

Part 4에서 이러한 문제를 다룰 것이다. 지금은 이 부분의 전체적인 차이점을 설명한다.

We'll address those issues in Part 4. For now, here's the complete diff from this part:
```diff
@@ -10,23 +10,94 @@ struct InputBuffer_t {
 };
 typedef struct InputBuffer_t InputBuffer;
 
+enum ExecuteResult_t { EXECUTE_SUCCESS, EXECUTE_TABLE_FULL };
+typedef enum ExecuteResult_t ExecuteResult;
+
 enum MetaCommandResult_t {
   META_COMMAND_SUCCESS,
   META_COMMAND_UNRECOGNIZED_COMMAND
 };
 typedef enum MetaCommandResult_t MetaCommandResult;
 
-enum PrepareResult_t { PREPARE_SUCCESS, PREPARE_UNRECOGNIZED_STATEMENT };
+enum PrepareResult_t {
+  PREPARE_SUCCESS,
+  PREPARE_SYNTAX_ERROR,
+  PREPARE_UNRECOGNIZED_STATEMENT
+};
 typedef enum PrepareResult_t PrepareResult;
 
 enum StatementType_t { STATEMENT_INSERT, STATEMENT_SELECT };
 typedef enum StatementType_t StatementType;
 
+const uint32_t COLUMN_USERNAME_SIZE = 32;
+const uint32_t COLUMN_EMAIL_SIZE = 255;
+struct Row_t {
+  uint32_t id;
+  char username[COLUMN_USERNAME_SIZE];
+  char email[COLUMN_EMAIL_SIZE];
+};
+typedef struct Row_t Row;
+
 struct Statement_t {
   StatementType type;
+  Row row_to_insert;  // only used by insert statement
 };
 typedef struct Statement_t Statement;
 
+const uint32_t ID_SIZE = sizeof(((Row*)0)->id);
+const uint32_t USERNAME_SIZE = sizeof(((Row*)0)->username);
+const uint32_t EMAIL_SIZE = sizeof(((Row*)0)->email);
+const uint32_t ID_OFFSET = 0;
+const uint32_t USERNAME_OFFSET = ID_OFFSET + ID_SIZE;
+const uint32_t EMAIL_OFFSET = USERNAME_OFFSET + USERNAME_SIZE;
+const uint32_t ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
+
+const uint32_t PAGE_SIZE = 4096;
+const uint32_t TABLE_MAX_PAGES = 100;
+const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
+const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
+
+struct Table_t {
+  void* pages[TABLE_MAX_PAGES];
+  uint32_t num_rows;
+};
+typedef struct Table_t Table;
+
+void print_row(Row* row) {
+  printf("(%d, %s, %s)\n", row->id, row->username, row->email);
+}
+
+void serialize_row(Row* source, void* destination) {
+  memcpy(destination + ID_OFFSET, &(source->id), ID_SIZE);
+  memcpy(destination + USERNAME_OFFSET, &(source->username), USERNAME_SIZE);
+  memcpy(destination + EMAIL_OFFSET, &(source->email), EMAIL_SIZE);
+}
+
+void deserialize_row(void* source, Row* destination) {
+  memcpy(&(destination->id), source + ID_OFFSET, ID_SIZE);
+  memcpy(&(destination->username), source + USERNAME_OFFSET, USERNAME_SIZE);
+  memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
+}
+
+void* row_slot(Table* table, uint32_t row_num) {
+  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  void* page = table->pages[page_num];
+  if (!page) {
+    // Allocate memory only when we try to access page
+    page = table->pages[page_num] = malloc(PAGE_SIZE);
+  }
+  uint32_t row_offset = row_num % ROWS_PER_PAGE;
+  uint32_t byte_offset = row_offset * ROW_SIZE;
+  return page + byte_offset;
+}
+
+Table* new_table() {
+  Table* table = malloc(sizeof(Table));
+  table->num_rows = 0;
+
+  return table;
+}
+
 InputBuffer* new_input_buffer() {
   InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
   input_buffer->buffer = NULL;
@@ -64,6 +135,12 @@ PrepareResult prepare_statement(InputBuffer* input_buffer,
                                 Statement* statement) {
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
     statement->type = STATEMENT_INSERT;
+    int args_assigned = sscanf(
+        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
+        statement->row_to_insert.username, statement->row_to_insert.email);
+    if (args_assigned < 3) {
+      return PREPARE_SYNTAX_ERROR;
+    }
     return PREPARE_SUCCESS;
   }
   if (strcmp(input_buffer->buffer, "select") == 0) {
@@ -74,18 +151,39 @@ PrepareResult prepare_statement(InputBuffer* input_buffer,
   return PREPARE_UNRECOGNIZED_STATEMENT;
 }
 
-void execute_statement(Statement* statement) {
+ExecuteResult execute_insert(Statement* statement, Table* table) {
+  if (table->num_rows >= TABLE_MAX_ROWS) {
+    return EXECUTE_TABLE_FULL;
+  }
+
+  Row* row_to_insert = &(statement->row_to_insert);
+
+  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  table->num_rows += 1;
+
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_select(Statement* statement, Table* table) {
+  Row row;
+  for (uint32_t i = 0; i < table->num_rows; i++) {
+    deserialize_row(row_slot(table, i), &row);
+    print_row(&row);
+  }
+  return EXECUTE_SUCCESS;
+}
+
+ExecuteResult execute_statement(Statement* statement, Table* table) {
   switch (statement->type) {
     case (STATEMENT_INSERT):
-      printf("This is where we would do an insert.\n");
-      break;
+      return execute_insert(statement, table);
     case (STATEMENT_SELECT):
-      printf("This is where we would do a select.\n");
-      break;
+      return execute_select(statement, table);
   }
 }
 
 int main(int argc, char* argv[]) {
+  Table* table = new_table();
   InputBuffer* input_buffer = new_input_buffer();
   while (true) {
     print_prompt();
@@ -105,13 +203,22 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_SYNTAX_ERROR):
+        printf("Syntax error. Could not parse statement.\n");
+        continue;
       case (PREPARE_UNRECOGNIZED_STATEMENT):
         printf("Unrecognized keyword at start of '%s'.\n",
                input_buffer->buffer);
         continue;
     }
 
-    execute_statement(&statement);
-    printf("Executed.\n");
+    switch (execute_statement(&statement, table)) {
+      case (PREPARE_SUCCESS):
+        printf("Executed.\n");
+        break;
+      case (EXECUTE_TABLE_FULL):
+        printf("Error: Table full.\n");
+        break;
+    }
   }
 }
```