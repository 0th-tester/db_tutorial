---
title: Part 11 - Recursively Searching the B-Tree
date: 2017-10-22
---

15번째 행 에러를 다루어보자.:

```
db > insert 15 user15 person15@example.com
Need to implement searching an internal node
```

새 함수 호출로 대체한다.

```diff
   if (get_node_type(root_node) == NODE_LEAF) {
     return leaf_node_find(table, root_page_num, key);
   } else {
-    printf("Need to implement searching an internal node\n");
-    exit(EXIT_FAILURE);
+    return internal_node_find(table, root_page_num, key);
   }
 }
```

이 함수는 주어진 키를 포함하는 자식 노드를 찾기위해 이진 탐색을 수행할 것이다.
각 자식 포인터의 오른쪽 키는 해당 자식의 키 중 가장 큰 값이다.

![three-level btree](../assets/images/btree6.png)

그렇기에 우리의 이진 탐색은 찾을 키와 자식 포인터 오른쪽에 있는 키를 비교한다.:

```diff
+Cursor* internal_node_find(Table* table, uint32_t page_num, uint32_t key) {
+  void* node = get_page(table->pager, page_num);
+  uint32_t num_keys = *internal_node_num_keys(node);
+
+  /* Binary search to find index of child to search */
+  uint32_t min_index = 0;
+  uint32_t max_index = num_keys; /* there is one more child than key */
+
+  while (min_index != max_index) {
+    uint32_t index = (min_index + max_index) / 2;
+    uint32_t key_to_right = *internal_node_key(node, index);
+    if (key_to_right >= key) {
+      max_index = index;
+    } else {
+      min_index = index + 1;
+    }
+  }
```

또한 인터널 노드의 자식들은 리프 노드 혹은 인터널 노드가 될 수 있다. 올바른 자식 노드를 찾은 후 해당 검색 기능을 호출해라.:

```diff
+  uint32_t child_num = *internal_node_child(node, min_index);
+  void* child = get_page(table->pager, child_num);
+  switch (get_node_type(child)) {
+    case NODE_LEAF:
+      return leaf_node_find(table, child_num, key);
+    case NODE_INTERNAL:
+      return internal_node_find(table, child_num, key);
+  }
+}
```

# Tests

이제 멀티 노드 btree에 키를 삽입해도 오류가 발생하지 않는다. 그리고 이제 테스트를 업데이트할 수 있다.:

```diff
       "    - 12",
       "    - 13",
       "    - 14",
-      "db > Need to implement searching an internal node",
+      "db > Executed.",
+      "db > ",
     ])
   end
```

또한 우리가 다른 시험을 다시 봐야 할 때라고 생각한다. 1400줄 삽입하는 거. 여전히 오류가 있지만 오류 메시지는 새롭다. 지금 당장은 프로그램이 고장나면 우리 시험이 잘 처리되지 않는다. 그렇게 되면 지금까지 얻은 결과만 사용하자.:

```diff
     raw_output = nil
     IO.popen("./db test.db", "r+") do |pipe|
       commands.each do |command|
-        pipe.puts command
+        begin
+          pipe.puts command
+        rescue Errno::EPIPE
+          break
+        end
       end

       pipe.close_write
```

1400행 테스트에서 이 오류가 출력됨을 알 수 있다.:

```diff
     end
     script << ".exit"
     result = run_script(script)
-    expect(result[-2]).to eq('db > Error: Table full.')
+    expect(result.last(2)).to eq([
+      "db > Executed.",
+      "db > Need to implement updating parent after split",
+    ])
   end
```

다음 할 일 목록이다!

