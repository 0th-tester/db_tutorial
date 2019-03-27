---
title: Part 9 - Binary Search and Duplicate Keys
date: 2017-10-01
---

지난 시간에 정렬되지 않게 키를 저장하는 것까지 했다. 기존 문제와 중복 키를 탐지하고 거부하는 로직도 구현해보자.

지금, `execute_insert()` 함수는 항상 테이블의 맨 끝에 삽입하게 되어 있다.
대신, 테이블에서 적절한 장소에 넣기 위해 찾고 그 곳에 데이터를 삽입한다. 그 곳에 키가 이미 있다면 에러를 반환한다.

```diff
ExecuteResult execute_insert(Statement* statement, Table* table) {
   void* node = get_page(table->pager, table->root_page_num);
-  if ((*leaf_node_num_cells(node) >= LEAF_NODE_MAX_CELLS)) {
+  uint32_t num_cells = (*leaf_node_num_cells(node));
+  if (num_cells >= LEAF_NODE_MAX_CELLS) {
     return EXECUTE_TABLE_FULL;
   }

   Row* row_to_insert = &(statement->row_to_insert);
-  Cursor* cursor = table_end(table);
+  uint32_t key_to_insert = row_to_insert->id;
+  Cursor* cursor = table_find(table, key_to_insert);
+
+  if (cursor->cell_num < num_cells) {
+    uint32_t key_at_index = *leaf_node_key(node, cursor->cell_num);
+    if (key_at_index == key_to_insert) {
+      return EXECUTE_DUPLICATE_KEY;
+    }
+  }

   leaf_node_insert(cursor, row_to_insert->id, row_to_insert);
```

`table_end()` 함수는 더 이상 필요하지 않다.

```diff
-Cursor* table_end(Table* table) {
-  Cursor* cursor = malloc(sizeof(Cursor));
-  cursor->table = table;
-  cursor->page_num = table->root_page_num;
-
-  void* root_node = get_page(table->pager, table->root_page_num);
-  uint32_t num_cells = *leaf_node_num_cells(root_node);
-  cursor->cell_num = num_cells;
-  cursor->end_of_table = true;
-
-  return cursor;
-}
```

주어진 키로 트리를 탐색하는 메소드로 대채할 것이다.

```diff
+/*
+Return the position of the given key.
+If the key is not present, return the position
+where it should be inserted
+*/
+Cursor* table_find(Table* table, uint32_t key) {
+  uint32_t root_page_num = table->root_page_num;
+  void* root_node = get_page(table->pager, root_page_num);
+
+  if (get_node_type(root_node) == NODE_LEAF) {
+    return leaf_node_find(table, root_page_num, key);
+  } else {
+    printf("Need to implement searching an internal node\n");
+    exit(EXIT_FAILURE);
+  }
+}
```

우리는 아직 인터널 노드를 구현하지 않았기 때문에 인터널 노드를 위해 분기를 걷어내고 있다. 이진 탐색으로 리프 노드를 탐색할 수 있다.

```diff
+Cursor* leaf_node_find(Table* table, uint32_t page_num, uint32_t key) {
+  void* node = get_page(table->pager, page_num);
+  uint32_t num_cells = *leaf_node_num_cells(node);
+
+  Cursor* cursor = malloc(sizeof(Cursor));
+  cursor->table = table;
+  cursor->page_num = page_num;
+
+  // Binary search
+  uint32_t min_index = 0;
+  uint32_t one_past_max_index = num_cells;
+  while (one_past_max_index != min_index) {
+    uint32_t index = (min_index + one_past_max_index) / 2;
+    uint32_t key_at_index = *leaf_node_key(node, index);
+    if (key == key_at_index) {
+      cursor->cell_num = index;
+      return cursor;
+    }
+    if (key < key_at_index) {
+      one_past_max_index = index;
+    } else {
+      min_index = index + 1;
+    }
+  }
+
+  cursor->cell_num = min_index;
+  return cursor;
+}
```

이 함수는 다음 경우 중 하나를 반환할 것이다.
- 해당 키의 위치 반환
- 새로운 키를 넣기를 원하면 움직이고 다른 키를 반환
- 마지막 키 이전 위치 반환

이제 노드 타입을 확인해야하기 때문에 노드 타입을 get/set 함수가 필요하다.

```diff
+NodeType get_node_type(void* node) {
+  uint8_t value = *((uint8_t*)(node + NODE_TYPE_OFFSET));
+  return (NodeType)value;
+}
+
+void set_node_type(void* node, NodeType type) {
+  uint8_t value = type;
+  *((uint8_t*)(node + NODE_TYPE_OFFSET)) = value;
+}
```

한 바이트로 직렬화되 있기 때문에 `uint8_t`로 캐스팅 해야한다.

노드 타입을 초기화해야한다.

```diff
-void initialize_leaf_node(void* node) { *leaf_node_num_cells(node) = 0; }
+void initialize_leaf_node(void* node) {
+  set_node_type(node, NODE_LEAF);
+  *leaf_node_num_cells(node) = 0;
+}
```

이제는 새 에러 코드를 다루어야 한다.

```diff
-enum ExecuteResult_t { EXECUTE_SUCCESS, EXECUTE_TABLE_FULL };
+enum ExecuteResult_t {
+  EXECUTE_SUCCESS,
+  EXECUTE_DUPLICATE_KEY,
+  EXECUTE_TABLE_FULL
+};
```

```diff
       case (EXECUTE_SUCCESS):
         printf("Executed.\n");
         break;
+      case (EXECUTE_DUPLICATE_KEY):
+        printf("Error: Duplicate key.\n");
+        break;
       case (EXECUTE_TABLE_FULL):
         printf("Error: Table full.\n");
         break;
```

이런 변화는 테스트 코드도 맞게 변경해주야한다.:

```diff
       "db > Executed.",
       "db > Tree:",
       "leaf (size 3)",
-      "  - 0 : 3",
-      "  - 1 : 1",
-      "  - 2 : 2",
+      "  - 0 : 1",
+      "  - 1 : 2",
+      "  - 2 : 3",
       "db > "
     ])
   end
```

키가 중복될 경우의 테스트 케이스를 추가한다:

```diff
+  it 'prints an error message if there is a duplicate id' do
+    script = [
+      "insert 1 user1 person1@example.com",
+      "insert 1 user1 person1@example.com",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to eq([
+      "db > Executed.",
+      "db > Error: Duplicate key.",
+      "db > (1, user1, person1@example.com)",
+      "Executed.",
+      "db > ",
+    ])
+  end
```

다음 글은 리프 노드의 분할과 인터널 노드를 생성하는 코드를 구현해보자.