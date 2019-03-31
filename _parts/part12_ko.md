---
title: Part 12 - Scanning a Multi-Level B-Tree
date: 2017-11-11
---

다 계층 btree를 다룰 수 있게 되었지만 `select` 구문이랑 맞지 않게 되었다.

15개 행을 삽입하고 출력하는 테스트 케이스가 있다.

```diff
+  it 'prints all rows in a multi-level tree' do
+    script = []
+    (1..15).each do |i|
+      script << "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << "select"
+    script << ".exit"
+    result = run_script(script)
+
+    expect(result[15...result.length]).to eq([
+      "db > (1, user1, person1@example.com)",
+      "(2, user2, person2@example.com)",
+      "(3, user3, person3@example.com)",
+      "(4, user4, person4@example.com)",
+      "(5, user5, person5@example.com)",
+      "(6, user6, person6@example.com)",
+      "(7, user7, person7@example.com)",
+      "(8, user8, person8@example.com)",
+      "(9, user9, person9@example.com)",
+      "(10, user10, person10@example.com)",
+      "(11, user11, person11@example.com)",
+      "(12, user12, person12@example.com)",
+      "(13, user13, person13@example.com)",
+      "(14, user14, person14@example.com)",
+      "(15, user15, person15@example.com)",
+      "Executed.", "db > ",
+    ])
+  end
```

하지만 실제로는 다음과 같이 나온다.:

```
db > select
(2, user1, person1@example.com)
Executed.
```

한 줄만 인쇄할 뿐이고, 그 행은 손상된 것처럼 보인다 (ID가 username과 일치하지 않는 점).

테이블의 시작점에서 시작하는 `execute_select()`와 루트 노드의 0번 셀을 반환하는 `table_start()` 때문이다. 트리의 루트는 어떤 행도 포함하지 않은 인터널 노드이다.
출력되는 데이터는 루트 노드가 리프 노드일 때부터 그대로 남아 있었을 것이다.
`execute_select()`는  최좌측 리프 노드의 셀 0을 반환해야 한다.

기존 구현 내용을 제거하자:

```diff
-Cursor* table_start(Table* table) {
-  Cursor* cursor = malloc(sizeof(Cursor));
-  cursor->table = table;
-  cursor->page_num = table->root_page_num;
-  cursor->cell_num = 0;
-
-  void* root_node = get_page(table->pager, table->root_page_num);
-  uint32_t num_cells = *leaf_node_num_cells(root_node);
-  cursor->end_of_table = (num_cells == 0);
-
-  return cursor;
-}
```

그리고 키 0(최소 키)을 검색하는 새로운 구현을 추가하십시오. 테이블에 키 0이 존재하지 않더라도, 이 방법은 가장 낮은 id의 위치(최좌측 리프 노드의 시작)를 반환한다.

```diff
+Cursor* table_start(Table* table) {
+  Cursor* cursor =  table_find(table, 0);
+
+  void* node = get_page(table->pager, cursor->page_num);
+  uint32_t num_cells = *leaf_node_num_cells(node);
+  cursor->end_of_table = (num_cells == 0);
+
+  return cursor;
+}
```

이러한 변경에도 여전히 한 노드의 값만 행만 출력할 수 있다.: 

```
db > select
(1, user1, person1@example.com)
(2, user2, person2@example.com)
(3, user3, person3@example.com)
(4, user4, person4@example.com)
(5, user5, person5@example.com)
(6, user6, person6@example.com)
(7, user7, person7@example.com)
Executed.
db >
```

15 엔트리를 갖은 b-tree는 인터널 노드와 리프노드를 가지고 있고 구조는 이와 비슷하다.:

![structure of our btree](../assets/images/btree3.png)

전체 테이블을 스캔하기 위해 첫번째 리프 노드의 끝에 도달한 후 두번째 리프 노드로 건너 뛰어야 한다. 그렇게 하기 위해 "next_leaf"라는 해당 노드의 오른쪽에 있는 노드의 페이지 번호를 저장하는 필드를 정의할 것이다. 가장 오른쪽에 리프 노드는 `next_leaf` 값은 0으로 형제 노드를 나타내지 않는다.( 0번 페이지는 루트 노드로 예약되어 있다 ).

리프 노드 헤더에 새 필드를 추가해보자:

```diff
 const uint32_t LEAF_NODE_NUM_CELLS_SIZE = sizeof(uint32_t);
 const uint32_t LEAF_NODE_NUM_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
-const uint32_t LEAF_NODE_HEADER_SIZE =
-    COMMON_NODE_HEADER_SIZE + LEAF_NODE_NUM_CELLS_SIZE;
+const uint32_t LEAF_NODE_NEXT_LEAF_SIZE = sizeof(uint32_t);
+const uint32_t LEAF_NODE_NEXT_LEAF_OFFSET =
+    LEAF_NODE_NUM_CELLS_OFFSET + LEAF_NODE_NUM_CELLS_SIZE;
+const uint32_t LEAF_NODE_HEADER_SIZE = COMMON_NODE_HEADER_SIZE +
+                                       LEAF_NODE_NUM_CELLS_SIZE +
+                                       LEAF_NODE_NEXT_LEAF_SIZE;
 
 ```

새 필드에 접근하는 메소드도 추가하자:
```diff
+uint32_t* leaf_node_next_leaf(void* node) {
+  return node + LEAF_NODE_NEXT_LEAF_OFFSET;
+}
```

새 리프 노드를 초기화 할 때 `next_leaf`의 기본값은 0으로 설정한다.:

```diff
@@ -322,6 +330,7 @@ void initialize_leaf_node(void* node) {
   set_node_type(node, NODE_LEAF);
   set_node_root(node, false);
   *leaf_node_num_cells(node) = 0;
+  *leaf_node_next_leaf(node) = 0;  // 0 represents no sibling
 }
```

리프 노드가 언제 분리되든지 형제 노드 포인터는 업데이트되어야한다.
이전 리프 형제 노드는 새 리프 노드가 되고 새 리프 노드의 형제는 이전 리프 노드의 형제가 된다.

```diff
@@ -659,6 +671,8 @@ void leaf_node_split_and_insert(Cursor* cursor, uint32_t key, Row* value) {
   uint32_t new_page_num = get_unused_page_num(cursor->table->pager);
   void* new_node = get_page(cursor->table->pager, new_page_num);
   initialize_leaf_node(new_node);
+  *leaf_node_next_leaf(new_node) = *leaf_node_next_leaf(old_node);
+  *leaf_node_next_leaf(old_node) = new_page_num;
```

새 필드를 추가하는 것으로 많은 상수가 변경된다.:
```diff
   it 'prints constants' do
     script = [
       ".constants",
@@ -199,9 +228,9 @@ describe 'database' do
       "db > Constants:",
       "ROW_SIZE: 293",
       "COMMON_NODE_HEADER_SIZE: 6",
-      "LEAF_NODE_HEADER_SIZE: 10",
+      "LEAF_NODE_HEADER_SIZE: 14",
       "LEAF_NODE_CELL_SIZE: 297",
-      "LEAF_NODE_SPACE_FOR_CELLS: 4086",
+      "LEAF_NODE_SPACE_FOR_CELLS: 4082",
       "LEAF_NODE_MAX_CELLS: 13",
       "db > ",
     ])
```

이제 우리가 리프 노드의 끝을 지나 커서를 전진시키고 싶을 때마다, 우리는 리프 노드에 형제 노드가 있는지 확인할 수 있다. 만약 그렇다면, 그곳으로 뛰어와라. 그렇지 않으면 우리는 테이블 끝에 있다.

```diff
@@ -428,7 +432,15 @@ void cursor_advance(Cursor* cursor) {
 
   cursor->cell_num += 1;
   if (cursor->cell_num >= (*leaf_node_num_cells(node))) {
-    cursor->end_of_table = true;
+    /* Advance to next leaf node */
+    uint32_t next_page_num = *leaf_node_next_leaf(node);
+    if (next_page_num == 0) {
+      /* This was rightmost leaf */
+      cursor->end_of_table = true;
+    } else {
+      cursor->page_num = next_page_num;
+      cursor->cell_num = 0;
+    }
   }
 }
```

이렇게 변경한 후 15개  행을 출력한다...
```
db > select
(1, user1, person1@example.com)
(2, user2, person2@example.com)
(3, user3, person3@example.com)
(4, user4, person4@example.com)
(5, user5, person5@example.com)
(6, user6, person6@example.com)
(7, user7, person7@example.com)
(8, user8, person8@example.com)
(9, user9, person9@example.com)
(10, user10, person10@example.com)
(11, user11, person11@example.com)
(12, user12, person12@example.com)
(13, user13, person13@example.com)
(1919251317, 14, on14@example.com)
(15, user15, person15@example.com)
Executed.
db >
```

하지만 행 중 하나가 깨져있다.
```
(1919251317, 14, on14@example.com)
```

디버깅 한 후 , 리프 노드의 분할할 때 버그가 발견했다.:

```diff
@@ -676,7 +690,9 @@ void leaf_node_split_and_insert(Cursor* cursor, uint32_t key, Row* value) {
     void* destination = leaf_node_cell(destination_node, index_within_node);
 
     if (i == cursor->cell_num) {
-      serialize_row(value, destination);
+      serialize_row(value,
+                    leaf_node_value(destination_node, index_within_node));
+      *leaf_node_key(destination_node, index_within_node) = key;
     } else if (i > cursor->cell_num) {
       memcpy(destination, leaf_node_cell(old_node, i - 1), LEAF_NODE_CELL_SIZE);
     } else {
```

리프 노드의 각 셀은 먼저 키와 다음 값으로 구성된다는 점을 기억해라.:

![Original leaf node format](../assets/images/leaf-node-format.png)

우리는 키가 가야 할 셀의 시작 부분에 새로운 행(값)을 쓰고 있었다.
이는 username의 일부가 ID를 위한 구역으로 들어가고 있었다는 것을 의미한다. ( 그렇기 때문에 id 값이 이상한 것이다. )

버그 수정 후 기대되는 전체 테이블을 출력했다.:

```
db > select
(1, user1, person1@example.com)
(2, user2, person2@example.com)
(3, user3, person3@example.com)
(4, user4, person4@example.com)
(5, user5, person5@example.com)
(6, user6, person6@example.com)
(7, user7, person7@example.com)
(8, user8, person8@example.com)
(9, user9, person9@example.com)
(10, user10, person10@example.com)
(11, user11, person11@example.com)
(12, user12, person12@example.com)
(13, user13, person13@example.com)
(14, user14, person14@example.com)
(15, user15, person15@example.com)
Executed.
db >
```
