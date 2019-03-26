---
title: Part 6 - The Cursor Abstraction
date: 2017-09-10
---

B-tree 구현을 쉽게 하기 위해 약간 리펙토링을 해보자.

테이블 위치를 표시할 `Cursor` 객체를 추가할 것이다. 구현할 `Curser` 기능은 다음과 같다.:

- 테이블 시작 부분에 커서 생성
- 테이블 끝 부분에 커서 생성
- 커서가 가리키는 행에 액세스
- 커서를 다음 행으로 이동

이것이 우리가 지금 구현할 것들이다. 나중에, 다음과 같은 기능을 원할 것이다.

- 커서에 의해 가리킨 행 삭제
- 커서에 의해 가리킨 행 수정
- 테이블에서 지정된 ID를 검색하고 해당 ID로 행을 가리키는 커서 생성.

다음과 같은 `Cursor` 타입이 있다.

```diff
+struct Cursor_t {
+  Table* table;
+  uint32_t row_num;
+  bool end_of_table;  // Indicates a position one past the last element
+};
+typedef struct Cursor_t Cursor;
```

현재 테이블 구조를 고려할 때 테이블에서 위치를 식별하는 데 필요한 것은 행 번호 뿐이다.

커서는 테이블의 일부와 연관성을 갖고 있다. (그래서 우리의 커서 기능은 커서를 파라미터로 받아들일 수 있다).

커서는 `end_of_table`라는 boolean을 갖고 있다.
이것은 테이블의 끝을 지나서 위치를 표현할 수 있기 때문이다. (행을 삽입 할 수도 있다).

`table_start()`과 `table_end()`는 새로운 커서를 생성한다.:

```diff
+Cursor* table_start(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = 0;
+  cursor->end_of_table = (table->num_rows == 0);
+
+  return cursor;
+}
+
+Cursor* table_end(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = table->num_rows;
+  cursor->end_of_table = true;
+
+  return cursor;
+}
```

`row_slot()` 함수는 `cursor_value()`로 커서에 정의된 위치를 가리키는 포인터를 반환하는 함수가 될 것이다.:

```diff
-void* row_slot(Table* table, uint32_t row_num) {
+void* cursor_value(Cursor* cursor) {
+  uint32_t row_num = cursor->row_num;
   uint32_t page_num = row_num / ROWS_PER_PAGE;
-  void* page = get_page(table->pager, page_num);
+  void* page = get_page(cursor->table->pager, page_num);
   uint32_t row_offset = row_num % ROWS_PER_PAGE;
   uint32_t byte_offset = row_offset * ROW_SIZE;
   return page + byte_offset;
 }
```

현재 테이블 구조에서 커서를 앞당기는 것은 행 번호를 증가시키는 것만큼 간단하다.
B-tree에선 약간 더 복잡할 것이다. 

```diff
+void cursor_advance(Cursor* cursor) {
+  cursor->row_num += 1;
+  if (cursor->row_num >= cursor->table->num_rows) {
+    cursor->end_of_table = true;
+  }
+}
```

마지막으로 커서 추상화를 이용하기 위해 "가상 머신" 메소드를 변경할 것이다. 행을 삽입할 때, 테이블의 끝 커서를 열고 커서가 닫히기 전에 커서 위치를 기록할 것이다.

```diff
   Row* row_to_insert = &(statement->row_to_insert);
+  Cursor* cursor = table_end(table);

-  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  serialize_row(row_to_insert, cursor_value(cursor));
   table->num_rows += 1;

+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
 ```

테이블에 모든 행을 선택한다면, 테이블의 시작 커서를 열고 다음 행으로 커서를 가리키고 행을 출력할 것이다. 테이블의 끝에 도달할 때까지 반복한다.

```diff
 ExecuteResult execute_select(Statement* statement, Table* table) {
+  Cursor* cursor = table_start(table);
+
   Row row;
-  for (uint32_t i = 0; i < table->num_rows; i++) {
-    deserialize_row(row_slot(table, i), &row);
+  while (!(cursor->end_of_table)) {
+    deserialize_row(cursor_value(cursor), &row);
     print_row(&row);
+    cursor_advance(cursor);
   }
+
+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
 ```

이전에 말했듯이, 이것은 우리의 테이블 데이터 구조를 B-Tree로 재 작성 할 때 우리를 도와 줄 수 있는 더 짧은 리팩토링이다.
`execute_select()`와 `execute_insert()`는 테이블이 저장되는 방법을 전혀 가정하지 않고 커서를 통해 테이블과 완전히 상호 작용할 수 있다.

이전과 다른 부분이다.:
```diff
 };
 typedef struct Table_t Table;
 
+struct Cursor_t {
+  Table* table;
+  uint32_t row_num;
+  bool end_of_table;  // Indicates a position one past the last element
+};
+typedef struct Cursor_t Cursor;
+
 void print_row(Row* row) {
   printf("(%d, %s, %s)\n", row->id, row->username, row->email);
 }
@@ -125,14 +132,40 @@ void* get_page(Pager* pager, uint32_t page_num) {
   return pager->pages[page_num];
 }
 
-void* row_slot(Table* table, uint32_t row_num) {
+Cursor* table_start(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = 0;
+  cursor->end_of_table = (table->num_rows == 0);
+
+  return cursor;
+}
+
+Cursor* table_end(Table* table) {
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->row_num = table->num_rows;
+  cursor->end_of_table = true;
+
+  return cursor;
+}
+
+void* cursor_value(Cursor* cursor) {
+  uint32_t row_num = cursor->row_num;
   uint32_t page_num = row_num / ROWS_PER_PAGE;
-  void* page = get_page(table->pager, page_num);
+  void* page = get_page(cursor->table->pager, page_num);
   uint32_t row_offset = row_num % ROWS_PER_PAGE;
   uint32_t byte_offset = row_offset * ROW_SIZE;
   return page + byte_offset;
 }
 
+void cursor_advance(Cursor* cursor) {
+  cursor->row_num += 1;
+  if (cursor->row_num >= cursor->table->num_rows) {
+    cursor->end_of_table = true;
+  }
+}
+
 Pager* pager_open(const char* filename) {
   int fd = open(filename,
                 O_RDWR |      // Read/Write mode
@@ -315,19 +348,28 @@ ExecuteResult execute_insert(Statement* statement, Table* table) {
   }
 
   Row* row_to_insert = &(statement->row_to_insert);
+  Cursor* cursor = table_end(table);
 
-  serialize_row(row_to_insert, row_slot(table, table->num_rows));
+  serialize_row(row_to_insert, cursor_value(cursor));
   table->num_rows += 1;
 
+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
 
 ExecuteResult execute_select(Statement* statement, Table* table) {
+  Cursor* cursor = table_start(table);
+
   Row row;
-  for (uint32_t i = 0; i < table->num_rows; i++) {
-    deserialize_row(row_slot(table, i), &row);
+  while (!(cursor->end_of_table)) {
+    deserialize_row(cursor_value(cursor), &row);
     print_row(&row);
+    cursor_advance(cursor);
   }
+
+  free(cursor);
+
   return EXECUTE_SUCCESS;
 }
 

```