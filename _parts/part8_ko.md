---
title: Part 8 - B-Tree Leaf Node Format
date: 2017-09-25
---

우리는 정렬되지 않은 배열에서 B-Tree로 테이블 포뱃을 변경 할 것이다. 이 글이 끝날 때쯤, 우리는 리프 노드의 계층을 정의하고 한 노드에 key/value 쌍을 넣는 것을 지원할 것이다. 하지만 먼저 트리 구조로 전환하는 이유를 다시 정리해보자.

## Alternative Table Formats

현재 포맷으로는 각 페이지는 ( 메타데이터 없이 ) 오직 행만 저장되기 때문에 꽤 공간 효율적이다. 끝에 추가했기만 했기 때문에 삽입 또한 빠르다. 그러나, 특정 행을 찾는 것은 전체 테이블을 스캔하는 것으로써 할 수 있다. 그리고 행을 삭제한다면, 빈 부분을 매꾸어야 하기 때문에 모든 행을 옮길 것이다.

배열로써 테이블을 저장하면, id에 의해 행은 정렬된다. 우리는 특정 id를 찾기 위해 
 이진 탐색을 이용할 수 있었다. 하지만 삽입은 삭제처럼 많은 행을 넣을 공간을 만들기 위해 옮겨야하는 같은 문제를 가지고 있다. 

대신, 트리 구조를 이용해보자. 트리의 각 노드는 가변적인 행 수를 포함할 수 있으므로, 우리는 그것이 얼마나 많은 행을 포함하는지를 추적하기 위해 각 노드에 정보를 저장해야 한다. 또한 행을 저장하지 않는 모든 내부 노드의 스토리지 오버헤드가 있다. 더 커진 데이터베이스 파일 대신, 우리는 빠른 삽입, 삭제, 조회가 가능해진다.

|               | Unsorted Array of rows | Sorted Array of rows | Tree of nodes |
|---------------|------------------------|----------------------|---------------|
| Pages contain | only data              | only data            | metadata, primary keys, and data              |
| Rows per page | more                   | more                 | fewer         |
| Insertion     | O(1)                   | O(n)                 | O(log(n))     |
| Deletion      | O(n)                   | O(n)                 | O(log(n))     |
| Lookup by id  | O(n)                   | O(log(n))            | O(log(n))     |

## Node Header Format

리프 노드와 인터널 노드는 다른 계층을 갖고 있다. 노드 타입을 추적하기 위해 
 열거(enum) 형을 만들자.:

```diff
+enum NodeType_t { NODE_INTERNAL, NODE_LEAF };
+typedef enum NodeType_t NodeType;
```

각 노드는 한 페이지에 대응될 것이다. 인터널 노드는 자식 노드를 저장하는 페이지 번호를 저장하여 자식 노드들을 가리킬 것이다. B-Tree는 pager에 특정 페이지 번호를 요청하고 페이지 캐시에서 포인터를 받게 된다. 페이지는 페이지 번호 순서대로 차례로 데이터베이스 파일에 저장된다.

노드들은 페이지의 시작하는 헤더 내에 메타데이터를 저장 해야 한다. 모든 노드는 노드 타입과 루트 노드 여부와 노드의 부모 포인터 등을 저장해야 한다.  (노드의 형제자매를 찾을 수 있도록 허용) . 모든 헤더 필드의 크기와 오프셋을 상수로 정의한다.:

```diff
+/*
+ * Common Node Header Layout
+ */
+const uint32_t NODE_TYPE_SIZE = sizeof(uint8_t);
+const uint32_t NODE_TYPE_OFFSET = 0;
+const uint32_t IS_ROOT_SIZE = sizeof(uint8_t);
+const uint32_t IS_ROOT_OFFSET = NODE_TYPE_SIZE;
+const uint32_t PARENT_POINTER_SIZE = sizeof(uint32_t);
+const uint32_t PARENT_POINTER_OFFSET = IS_ROOT_OFFSET + IS_ROOT_SIZE;
+const uint8_t COMMON_NODE_HEADER_SIZE =
+    NODE_TYPE_SIZE + IS_ROOT_SIZE + PARENT_POINTER_SIZE;
```

## Leaf Node Format

공통 헤더 필드로는 리프 노드는 얼마나 많은 "cells"를 포함할 지에 대해 저장해야한다. 여기서 셀(cell)는 key/value 쌍이다.

```diff
+/*
+ * Leaf Node Header Layout
+ */
+const uint32_t LEAF_NODE_NUM_CELLS_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_NUM_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_HEADER_SIZE =
+    COMMON_NODE_HEADER_SIZE + LEAF_NODE_NUM_CELLS_SIZE;
```

리프 노드의 본문은 셀의 배열이다. 각 셀은 키 다음에 값(시리얼화된 행)이 뒤따른다.

```diff
+/*
+ * Leaf Node Body Layout
+ */
+const uint32_t LEAF_NODE_KEY_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_KEY_OFFSET = 0;
+const uint32_t LEAF_NODE_VALUE_SIZE = ROW_SIZE;
+const uint32_t LEAF_NODE_VALUE_OFFSET =
+    LEAF_NODE_KEY_OFFSET + LEAF_NODE_KEY_SIZE;
+const uint32_t LEAF_NODE_CELL_SIZE = LEAF_NODE_KEY_SIZE + LEAF_NODE_VALUE_SIZE;
+const uint32_t LEAF_NODE_SPACE_FOR_CELLS = PAGE_SIZE - LEAF_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_MAX_CELLS =
+    LEAF_NODE_SPACE_FOR_CELLS / LEAF_NODE_CELL_SIZE;
```

이러한 상수를 기반으로 현재 리프 노드의 계층을 살펴보자.:

![Our leaf node format](../assets/images/leaf-node-format.png)

헤더 안에 boolean 당 한 바이트 전체는 비효율적이지만 이는 이런 값에 접근하는 코드를 작성하기 쉽게 만든다.

또한 끝에 낭비되는 공간이 있음을 주목하자. 헤더 다음에 가능한 한 많은 셀을 저장하지만 나머지 공간은 전체 셀을 보유 할 수 없다. 노드 간에 셀을 나누지 않으려면 비워 둔다.

## Accessing Leaf Node Fields

키, 값 및 메타 데이터에 액세스하는 코드에는 방금 정의한 상수를 사용하는 포인터 산술 연산이 포함된다.

```diff
+uint32_t* leaf_node_num_cells(void* node) {
+  return node + LEAF_NODE_NUM_CELLS_OFFSET;
+}
+
+void* leaf_node_cell(void* node, uint32_t cell_num) {
+  return node + LEAF_NODE_HEADER_SIZE + cell_num * LEAF_NODE_CELL_SIZE;
+}
+
+uint32_t* leaf_node_key(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num);
+}
+
+void* leaf_node_value(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num) + LEAF_NODE_KEY_SIZE;
+}
+
+void initialize_leaf_node(void* node) { *leaf_node_num_cells(node) = 0; }
+
```

이 메소드는 요청한 값의 포인터를 반환하기 때문에 getter, setter 둘 다 이용할 수 있다.

## Changes to Pager and Table Objects

비록 가득차지 않더라도 모든 노드가 한 페이지를 차지할 것이다. pager가 더 이상 부분 읽기/쓰기를 지원할 필요가 없다는 것을 의미한다. 
```diff
-void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
+void pager_flush(Pager* pager, uint32_t page_num) {
   if (pager->pages[page_num] == NULL) {
     printf("Tried to flush null page\n");
     exit(EXIT_FAILURE);
@@ -242,7 +337,7 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
   }
 
   ssize_t bytes_written =
-      write(pager->file_descriptor, pager->pages[page_num], size);
+      write(pager->file_descriptor, pager->pages[page_num], PAGE_SIZE);
 
   if (bytes_written == -1) {
     printf("Error writing: %d\n", errno);
```

```diff
 void db_close(Table* table) {
   Pager* pager = table->pager;
-  uint32_t num_full_pages = table->num_rows / ROWS_PER_PAGE;
 
-  for (uint32_t i = 0; i < num_full_pages; i++) {
+  for (uint32_t i = 0; i < pager->num_pages; i++) {
     if (pager->pages[i] == NULL) {
       continue;
     }
-    pager_flush(pager, i, PAGE_SIZE);
+    pager_flush(pager, i);
     free(pager->pages[i]);
     pager->pages[i] = NULL;
   }
 
-  // There may be a partial page to write to the end of the file
-  // This should not be needed after we switch to a B-tree
-  uint32_t num_additional_rows = table->num_rows % ROWS_PER_PAGE;
-  if (num_additional_rows > 0) {
-    uint32_t page_num = num_full_pages;
-    if (pager->pages[page_num] != NULL) {
-      pager_flush(pager, page_num, num_additional_rows * ROW_SIZE);
-      free(pager->pages[page_num]);
-      pager->pages[page_num] = NULL;
-    }
-  }
-
   int result = close(pager->file_descriptor);
   if (result == -1) {
     printf("Error closing db file.\n");
```

이제 행 수보다는 우리 데이터베이스에 페이지 수를 저장하는 것이 더 적절하다.
페이지 수는 특정 테이블이 아니라 데이터베이스에서 사용하는 페이지 수이므로 테이블이 아니라 pager 객체와 연관되어야 한다. B-tree는 루트 노드 페이지 번호에 식별되기 때문에 테이블 객체는 이를 계속 추적할 필요가 있다.

```diff
 const uint32_t PAGE_SIZE = 4096;
 const uint32_t TABLE_MAX_PAGES = 100;
-const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
-const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
 
 struct Pager_t {
   int file_descriptor;
   uint32_t file_length;
+  uint32_t num_pages;
   void* pages[TABLE_MAX_PAGES];
 };
 typedef struct Pager_t Pager;
 
 struct Table_t {
   Pager* pager;
-  uint32_t num_rows;
+  uint32_t root_page_num;
 };
 typedef struct Table_t Table;
```

```diff
@@ -127,6 +200,10 @@ void* get_page(Pager* pager, uint32_t page_num) {
     }
 
     pager->pages[page_num] = page;
+
+    if (page_num >= pager->num_pages) {
+      pager->num_pages = page_num + 1;
+    }
   }
 
   return pager->pages[page_num];
```

```diff
@@ -184,6 +269,12 @@ Pager* pager_open(const char* filename) {
   Pager* pager = malloc(sizeof(Pager));
   pager->file_descriptor = fd;
   pager->file_length = file_length;
+  pager->num_pages = (file_length / PAGE_SIZE);
+
+  if (file_length % PAGE_SIZE != 0) {
+    printf("Db file is not a whole number of pages. Corrupt file.\n");
+    exit(EXIT_FAILURE);
+  }
 
   for (uint32_t i = 0; i < TABLE_MAX_PAGES; i++) {
     pager->pages[i] = NULL;
```

## Changes to the Cursor Object

커서는 테이블 내 위치를 표현한다. 테이블이 행의 간단한 배열일때는 행의 번호로만 접근하면 됬었다. 지금은 트리이기 때문에 노드의 페이지 번호와 노드 안에 셀 번호에 따라 위치를 식별한다.

```diff
 struct Cursor_t {
   Table* table;
-  uint32_t row_num;
+  uint32_t page_num;
+  uint32_t cell_num;
   bool end_of_table;  // Indicates a position one past the last element
 };
 typedef struct Cursor_t Cursor;
```

```diff
 Cursor* table_start(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = 0;
-  cursor->end_of_table = (table->num_rows == 0);
+  cursor->page_num = table->root_page_num;
+  cursor->cell_num = 0;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->end_of_table = (num_cells == 0);
 
   return cursor;
 }
```

```diff
 Cursor* table_end(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = table->num_rows;
+  cursor->page_num = table->root_page_num;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->cell_num = num_cells;
   cursor->end_of_table = true;
 
   return cursor;
 }
```

```diff
 void* cursor_value(Cursor* cursor) {
-  uint32_t row_num = cursor->row_num;
-  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  uint32_t page_num = cursor->page_num;
   void* page = get_page(cursor->table->pager, page_num);
-  uint32_t row_offset = row_num % ROWS_PER_PAGE;
-  uint32_t byte_offset = row_offset * ROW_SIZE;
-  return page + byte_offset;
+  return leaf_node_value(page, cursor->cell_num);
 }
```

```diff
 void cursor_advance(Cursor* cursor) {
-  cursor->row_num += 1;
-  if (cursor->row_num >= cursor->table->num_rows) {
+  uint32_t page_num = cursor->page_num;
+  void* node = get_page(cursor->table->pager, page_num);
+
+  cursor->cell_num += 1;
+  if (cursor->cell_num >= (*leaf_node_num_cells(node))) {
     cursor->end_of_table = true;
   }
 }
```

## Insertion Into a Leaf Node

이 글에서 우리는 싱글 노드 트리를 얻을 수 있을 정도로만 구현할 것이다.
지난 글에서 트리가 빈 리프 노드로 시작한다는 점을 상기해보자.:

![empty btree](../assets/images/btree1.png)

key/value 쌍은 리프 노드가 가득 찰 때까지 추가할 수 있다.:

![one-node btree](../assets/images/btree2.png)

처음 데이터베이스를 열 때 데이터베이스 파일은 비어있기 때문에 빈 리프 노드로 페이지 0으로 초기화한다. ( 루트 노드 ):

```diff
 Table* db_open(const char* filename) {
   Pager* pager = pager_open(filename);
-  uint32_t num_rows = pager->file_length / ROW_SIZE;
 
   Table* table = malloc(sizeof(Table));
   table->pager = pager;
-  table->num_rows = num_rows;
+
+  if (pager->num_pages == 0) {
+    // New database file. Initialize page 0 as leaf node.
+    void* root_node = get_page(pager, 0);
+    initialize_leaf_node(root_node);
+  }
 
   return table;
 }
```

다음으로 key/value 쌍을 리프 노드에 넣는 함수를 구현할 것이다. 커서가 입력으로 페어를 삽입해야 하는 위치를 나타내야 한다.

```diff
+void leaf_node_insert(Cursor* cursor, uint32_t key, Row* value) {
+  void* node = get_page(cursor->table->pager, cursor->page_num);
+
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  if (num_cells >= LEAF_NODE_MAX_CELLS) {
+    // Node full
+    printf("Need to implement splitting a leaf node.\n");
+    exit(EXIT_FAILURE);
+  }
+
+  if (cursor->cell_num < num_cells) {
+    // Make room for new cell
+    for (uint32_t i = num_cells; i > cursor->cell_num; i--) {
+      memcpy(leaf_node_cell(node, i), leaf_node_cell(node, i - 1),
+             LEAF_NODE_CELL_SIZE);
+    }
+  }
+
+  *(leaf_node_num_cells(node)) += 1;
+  *(leaf_node_key(node, cursor->cell_num)) = key;
+  serialize_row(value, leaf_node_value(node, cursor->cell_num));
+}
+
```

우린 아직 노드의 분할을 구현하지 않았기 때문에 노드가 가득 차면 에러를 발생하자.
다음으로 우리는 셀들을 오른쪽으로 한 칸 옮겨서 새로운 셀을 위한 공간을 만든다. 그런 다음 빈 공간에 새 key/value을 기록한다.

노드 하나로 가정하기 때문에 `execute_insert()` 함수는 헬퍼 메소드를 호출할 필요가 있다.:

Since we assume the tree only has one node, our `execute_insert()` function simply needs to call this helper method:

```diff
 ExecuteResult execute_insert(Statement* statement, Table* table) {
-  if (table->num_rows >= TABLE_MAX_ROWS) {
+  void* node = get_page(table->pager, table->root_page_num);
+  if ((*leaf_node_num_cells(node) >= LEAF_NODE_MAX_CELLS)) {
     return EXECUTE_TABLE_FULL;
   }
 
   Row* row_to_insert = &(statement->row_to_insert);
   Cursor* cursor = table_end(table);
 
-  serialize_row(row_to_insert, cursor_value(cursor));
-  table->num_rows += 1;
+  leaf_node_insert(cursor, row_to_insert->id, row_to_insert);
 
   free(cursor);
```

이러한 변화로 인해 데이터베이스는 이전 동작을 수행해야한다. 그러나 루트 노드를 아직 분할할 수 없기 때문에 훨씬 더 빨리 "Table Full" 오류를 반환한다.

리프 노드는 몇 개의 행을 저장할 수 있는가?

## Command to Print Constants

몇 개의 상수를 출력하기 위해 새로운 메타 명령을 추가한다.

```diff
+void print_constants() {
+  printf("ROW_SIZE: %d\n", ROW_SIZE);
+  printf("COMMON_NODE_HEADER_SIZE: %d\n", COMMON_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_HEADER_SIZE: %d\n", LEAF_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_CELL_SIZE: %d\n", LEAF_NODE_CELL_SIZE);
+  printf("LEAF_NODE_SPACE_FOR_CELLS: %d\n", LEAF_NODE_SPACE_FOR_CELLS);
+  printf("LEAF_NODE_MAX_CELLS: %d\n", LEAF_NODE_MAX_CELLS);
+}
+
@@ -294,6 +376,14 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table* table) {
   if (strcmp(input_buffer->buffer, ".exit") == 0) {
     db_close(table);
     exit(EXIT_SUCCESS);
+  } else if (strcmp(input_buffer->buffer, ".constants") == 0) {
+    printf("Constants:\n");
+    print_constants();
+    return META_COMMAND_SUCCESS;
   } else {
     return META_COMMAND_UNRECOGNIZED_COMMAND;
   }
```

테스트 케이스를 추가해서 상수가 변할 때 확인할 수 있다.:
```diff
+  it 'prints constants' do
+    script = [
+      ".constants",
+      ".exit",
+    ]
+    result = run_script(script)
+
+    expect(result).to eq([
+      "db > Constants:",
+      "ROW_SIZE: 293",
+      "COMMON_NODE_HEADER_SIZE: 6",
+      "LEAF_NODE_HEADER_SIZE: 10",
+      "LEAF_NODE_CELL_SIZE: 297",
+      "LEAF_NODE_SPACE_FOR_CELLS: 4086",
+      "LEAF_NODE_MAX_CELLS: 13",
+      "db > ",
+    ])
+  end
```

우리 테이블에는 13개 행을 저장할 수 있다!

## Tree Visualization

디버깅과 시각화를 위해 B-tree를 출력하기 위해 메타 명령을 추가하고 있다.

```diff
+void print_leaf_node(void* node) {
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  printf("leaf (size %d)\n", num_cells);
+  for (uint32_t i = 0; i < num_cells; i++) {
+    uint32_t key = *leaf_node_key(node, i);
+    printf("  - %d : %d\n", i, key);
+  }
+}
+
```

```diff
@@ -294,6 +376,14 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table* table) {
   if (strcmp(input_buffer->buffer, ".exit") == 0) {
     db_close(table);
     exit(EXIT_SUCCESS);
+  } else if (strcmp(input_buffer->buffer, ".btree") == 0) {
+    printf("Tree:\n");
+    print_leaf_node(get_page(table->pager, 0));
+    return META_COMMAND_SUCCESS;
   } else if (strcmp(input_buffer->buffer, ".constants") == 0) {
     printf("Constants:\n");
     print_constants();
     return META_COMMAND_SUCCESS;
   } else {
     return META_COMMAND_UNRECOGNIZED_COMMAND;
   }
```

테스트 해보자.

```diff
+  it 'allows printing out the structure of a one-node btree' do
+    script = [3, 1, 2].map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".btree"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result).to eq([
+      "db > Executed.",
+      "db > Executed.",
+      "db > Executed.",
+      "db > Tree:",
+      "leaf (size 3)",
+      "  - 0 : 3",
+      "  - 1 : 1",
+      "  - 2 : 2",
+      "db > "
+    ])
+  end
```

정렬된 순서의 행으로 저장되지 않는다. `execute_insert()`가 `table_end()`로 반환되는 위치에서 leaf 노드에 삽입되는 것을 알 수 있다. 그래서 행은 이전과 마찬가지로 삽입된 순서대로 저장된다.

## Next Time

이 모두가 이전 단계로 되돌아 간 것처럼 보인다. 데이터베이스는 이전보다 적은 수의 행을 저장하고 정렬되지 않은 순서로 행을 저장한다. 그러나 내가 처음에 말했듯이, 이것은 큰 변화이며, 그것을 관리 가능한 단계로 나누는 것이 중요하다.

다음에는 프라이머리 키로 레코드 찾기를 구현하고 정렬 된 순서로 행을 저장하기 시작할 것이다.

## Complete Diff

```diff
 const uint32_t PAGE_SIZE = 4096;
 const uint32_t TABLE_MAX_PAGES = 100;
-const uint32_t ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
-const uint32_t TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;
 
 struct Pager_t {
   int file_descriptor;
   uint32_t file_length;
+  uint32_t num_pages;
   void* pages[TABLE_MAX_PAGES];
 };
 typedef struct Pager_t Pager;
 
 struct Table_t {
   Pager* pager;
-  uint32_t num_rows;
+  uint32_t root_page_num;
 };
 typedef struct Table_t Table;
 
 struct Cursor_t {
   Table* table;
-  uint32_t row_num;
+  uint32_t page_num;
+  uint32_t cell_num;
   bool end_of_table;  // Indicates a position one past the last element
 };
 typedef struct Cursor_t Cursor;
@@ -88,6 +88,77 @@ void print_row(Row* row) {
   printf("(%d, %s, %s)\n", row->id, row->username, row->email);
 }
 
+enum NodeType_t { NODE_INTERNAL, NODE_LEAF };
+typedef enum NodeType_t NodeType;
+
+/*
+ * Common Node Header Layout
+ */
+const uint32_t NODE_TYPE_SIZE = sizeof(uint8_t);
+const uint32_t NODE_TYPE_OFFSET = 0;
+const uint32_t IS_ROOT_SIZE = sizeof(uint8_t);
+const uint32_t IS_ROOT_OFFSET = NODE_TYPE_SIZE;
+const uint32_t PARENT_POINTER_SIZE = sizeof(uint32_t);
+const uint32_t PARENT_POINTER_OFFSET = IS_ROOT_OFFSET + IS_ROOT_SIZE;
+const uint8_t COMMON_NODE_HEADER_SIZE =
+    NODE_TYPE_SIZE + IS_ROOT_SIZE + PARENT_POINTER_SIZE;
+
+/*
+ * Leaf Node Header Layout
+ */
+const uint32_t LEAF_NODE_NUM_CELLS_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_NUM_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_HEADER_SIZE =
+    COMMON_NODE_HEADER_SIZE + LEAF_NODE_NUM_CELLS_SIZE;
+
+/*
+ * Leaf Node Body Layout
+ */
+const uint32_t LEAF_NODE_KEY_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_KEY_OFFSET = 0;
+const uint32_t LEAF_NODE_VALUE_SIZE = ROW_SIZE;
+const uint32_t LEAF_NODE_VALUE_OFFSET =
+    LEAF_NODE_KEY_OFFSET + LEAF_NODE_KEY_SIZE;
+const uint32_t LEAF_NODE_CELL_SIZE = LEAF_NODE_KEY_SIZE + LEAF_NODE_VALUE_SIZE;
+const uint32_t LEAF_NODE_SPACE_FOR_CELLS = PAGE_SIZE - LEAF_NODE_HEADER_SIZE;
+const uint32_t LEAF_NODE_MAX_CELLS =
+    LEAF_NODE_SPACE_FOR_CELLS / LEAF_NODE_CELL_SIZE;
+
+uint32_t* leaf_node_num_cells(void* node) {
+  return node + LEAF_NODE_NUM_CELLS_OFFSET;
+}
+
+void* leaf_node_cell(void* node, uint32_t cell_num) {
+  return node + LEAF_NODE_HEADER_SIZE + cell_num * LEAF_NODE_CELL_SIZE;
+}
+
+uint32_t* leaf_node_key(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num);
+}
+
+void* leaf_node_value(void* node, uint32_t cell_num) {
+  return leaf_node_cell(node, cell_num) + LEAF_NODE_KEY_SIZE;
+}
+
+void print_constants() {
+  printf("ROW_SIZE: %d\n", ROW_SIZE);
+  printf("COMMON_NODE_HEADER_SIZE: %d\n", COMMON_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_HEADER_SIZE: %d\n", LEAF_NODE_HEADER_SIZE);
+  printf("LEAF_NODE_CELL_SIZE: %d\n", LEAF_NODE_CELL_SIZE);
+  printf("LEAF_NODE_SPACE_FOR_CELLS: %d\n", LEAF_NODE_SPACE_FOR_CELLS);
+  printf("LEAF_NODE_MAX_CELLS: %d\n", LEAF_NODE_MAX_CELLS);
+}
+
+void print_leaf_node(void* node) {
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  printf("leaf (size %d)\n", num_cells);
+  for (uint32_t i = 0; i < num_cells; i++) {
+    uint32_t key = *leaf_node_key(node, i);
+    printf("  - %d : %d\n", i, key);
+  }
+}
+
 void serialize_row(Row* source, void* destination) {
   memcpy(destination + ID_OFFSET, &(source->id), ID_SIZE);
   memcpy(destination + USERNAME_OFFSET, &(source->username), USERNAME_SIZE);
@@ -100,6 +171,8 @@ void deserialize_row(void* source, Row* destination) {
   memcpy(&(destination->email), source + EMAIL_OFFSET, EMAIL_SIZE);
 }
 
+void initialize_leaf_node(void* node) { *leaf_node_num_cells(node) = 0; }
+
 void* get_page(Pager* pager, uint32_t page_num) {
   if (page_num > TABLE_MAX_PAGES) {
     printf("Tried to fetch page number out of bounds. %d > %d\n", page_num,
@@ -127,6 +200,10 @@ void* get_page(Pager* pager, uint32_t page_num) {
     }
 
     pager->pages[page_num] = page;
+
+    if (page_num >= pager->num_pages) {
+      pager->num_pages = page_num + 1;
+    }
   }
 
   return pager->pages[page_num];
@@ -135,8 +212,12 @@ void* get_page(Pager* pager, uint32_t page_num) {
 Cursor* table_start(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = 0;
-  cursor->end_of_table = (table->num_rows == 0);
+  cursor->page_num = table->root_page_num;
+  cursor->cell_num = 0;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->end_of_table = (num_cells == 0);
 
   return cursor;
 }
@@ -144,24 +225,28 @@ Cursor* table_start(Table* table) {
 Cursor* table_end(Table* table) {
   Cursor* cursor = malloc(sizeof(Cursor));
   cursor->table = table;
-  cursor->row_num = table->num_rows;
+  cursor->page_num = table->root_page_num;
+
+  void* root_node = get_page(table->pager, table->root_page_num);
+  uint32_t num_cells = *leaf_node_num_cells(root_node);
+  cursor->cell_num = num_cells;
   cursor->end_of_table = true;
 
   return cursor;
 }
 
 void* cursor_value(Cursor* cursor) {
-  uint32_t row_num = cursor->row_num;
-  uint32_t page_num = row_num / ROWS_PER_PAGE;
+  uint32_t page_num = cursor->page_num;
   void* page = get_page(cursor->table->pager, page_num);
-  uint32_t row_offset = row_num % ROWS_PER_PAGE;
-  uint32_t byte_offset = row_offset * ROW_SIZE;
-  return page + byte_offset;
+  return leaf_node_value(page, cursor->cell_num);
 }
 
 void cursor_advance(Cursor* cursor) {
-  cursor->row_num += 1;
-  if (cursor->row_num >= cursor->table->num_rows) {
+  uint32_t page_num = cursor->page_num;
+  void* node = get_page(cursor->table->pager, page_num);
+
+  cursor->cell_num += 1;
+  if (cursor->cell_num >= (*leaf_node_num_cells(node))) {
     cursor->end_of_table = true;
   }
 }
@@ -184,6 +269,12 @@ Pager* pager_open(const char* filename) {
   Pager* pager = malloc(sizeof(Pager));
   pager->file_descriptor = fd;
   pager->file_length = file_length;
+  pager->num_pages = (file_length / PAGE_SIZE);
+
+  if (file_length % PAGE_SIZE != 0) {
+    printf("Db file is not a whole number of pages. Corrupt file.\n");
+    exit(EXIT_FAILURE);
+  }
 
   for (uint32_t i = 0; i < TABLE_MAX_PAGES; i++) {
     pager->pages[i] = NULL;
@@ -194,11 +285,15 @@ Pager* pager_open(const char* filename) {
 
 Table* db_open(const char* filename) {
   Pager* pager = pager_open(filename);
-  uint32_t num_rows = pager->file_length / ROW_SIZE;
 
   Table* table = malloc(sizeof(Table));
   table->pager = pager;
-  table->num_rows = num_rows;
+
+  if (pager->num_pages == 0) {
+    // New database file. Initialize page 0 as leaf node.
+    void* root_node = get_page(pager, 0);
+    initialize_leaf_node(root_node);
+  }
 
   return table;
 }
@@ -228,7 +323,7 @@ void read_input(InputBuffer* input_buffer) {
   input_buffer->buffer[bytes_read - 1] = 0;
 }
 
-void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
+void pager_flush(Pager* pager, uint32_t page_num) {
   if (pager->pages[page_num] == NULL) {
     printf("Tried to flush null page\n");
     exit(EXIT_FAILURE);
@@ -242,7 +337,7 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
   }
 
   ssize_t bytes_written =
-      write(pager->file_descriptor, pager->pages[page_num], size);
+      write(pager->file_descriptor, pager->pages[page_num], PAGE_SIZE);
 
   if (bytes_written == -1) {
     printf("Error writing: %d\n", errno);
@@ -252,29 +347,16 @@ void pager_flush(Pager* pager, uint32_t page_num, uint32_t size) {
 
 void db_close(Table* table) {
   Pager* pager = table->pager;
-  uint32_t num_full_pages = table->num_rows / ROWS_PER_PAGE;
 
-  for (uint32_t i = 0; i < num_full_pages; i++) {
+  for (uint32_t i = 0; i < pager->num_pages; i++) {
     if (pager->pages[i] == NULL) {
       continue;
     }
-    pager_flush(pager, i, PAGE_SIZE);
+    pager_flush(pager, i);
     free(pager->pages[i]);
     pager->pages[i] = NULL;
   }
 
-  // There may be a partial page to write to the end of the file
-  // This should not be needed after we switch to a B-tree
-  uint32_t num_additional_rows = table->num_rows % ROWS_PER_PAGE;
-  if (num_additional_rows > 0) {
-    uint32_t page_num = num_full_pages;
-    if (pager->pages[page_num] != NULL) {
-      pager_flush(pager, page_num, num_additional_rows * ROW_SIZE);
-      free(pager->pages[page_num]);
-      pager->pages[page_num] = NULL;
-    }
-  }
-
   int result = close(pager->file_descriptor);
   if (result == -1) {
     printf("Error closing db file.\n");
@@ -294,6 +376,14 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer, Table* table) {
   if (strcmp(input_buffer->buffer, ".exit") == 0) {
     db_close(table);
     exit(EXIT_SUCCESS);
+  } else if (strcmp(input_buffer->buffer, ".btree") == 0) {
+    printf("Tree:\n");
+    print_leaf_node(get_page(table->pager, 0));
+    return META_COMMAND_SUCCESS;
+  } else if (strcmp(input_buffer->buffer, ".constants") == 0) {
+    printf("Constants:\n");
+    print_constants();
+    return META_COMMAND_SUCCESS;
   } else {
     return META_COMMAND_UNRECOGNIZED_COMMAND;
   }
@@ -342,16 +432,39 @@ PrepareResult prepare_statement(InputBuffer* input_buffer,
   return PREPARE_UNRECOGNIZED_STATEMENT;
 }
 
+void leaf_node_insert(Cursor* cursor, uint32_t key, Row* value) {
+  void* node = get_page(cursor->table->pager, cursor->page_num);
+
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  if (num_cells >= LEAF_NODE_MAX_CELLS) {
+    // Node full
+    printf("Need to implement splitting a leaf node.\n");
+    exit(EXIT_FAILURE);
+  }
+
+  if (cursor->cell_num < num_cells) {
+    // Make room for new cell
+    for (uint32_t i = num_cells; i > cursor->cell_num; i--) {
+      memcpy(leaf_node_cell(node, i), leaf_node_cell(node, i - 1),
+             LEAF_NODE_CELL_SIZE);
+    }
+  }
+
+  *(leaf_node_num_cells(node)) += 1;
+  *(leaf_node_key(node, cursor->cell_num)) = key;
+  serialize_row(value, leaf_node_value(node, cursor->cell_num));
+}
+
 ExecuteResult execute_insert(Statement* statement, Table* table) {
-  if (table->num_rows >= TABLE_MAX_ROWS) {
+  void* node = get_page(table->pager, table->root_page_num);
+  if ((*leaf_node_num_cells(node) >= LEAF_NODE_MAX_CELLS)) {
     return EXECUTE_TABLE_FULL;
   }
 
   Row* row_to_insert = &(statement->row_to_insert);
   Cursor* cursor = table_end(table);
 
-  serialize_row(row_to_insert, cursor_value(cursor));
-  table->num_rows += 1;
+  leaf_node_insert(cursor, row_to_insert->id, row_to_insert);
 
   free(cursor);
```

And the specs:
```diff
+  it 'allows printing out the structure of a one-node btree' do
+    script = [3, 1, 2].map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".btree"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result).to eq([
+      "db > Executed.",
+      "db > Executed.",
+      "db > Executed.",
+      "db > Tree:",
+      "leaf (size 3)",
+      "  - 0 : 3",
+      "  - 1 : 1",
+      "  - 2 : 2",
+      "db > "
+    ])
+  end
+
+  it 'prints constants' do
+    script = [
+      ".constants",
+      ".exit",
+    ]
+    result = run_script(script)
+
+    expect(result).to eq([
+      "db > Constants:",
+      "ROW_SIZE: 293",
+      "COMMON_NODE_HEADER_SIZE: 6",
+      "LEAF_NODE_HEADER_SIZE: 10",
+      "LEAF_NODE_CELL_SIZE: 297",
+      "LEAF_NODE_SPACE_FOR_CELLS: 4086",
+      "LEAF_NODE_MAX_CELLS: 13",
+      "db > ",
+    ])
+  end
 end
```
