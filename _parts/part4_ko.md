
# Part 4 - Our First Tests (and Bugs)

우리는 데이터베이스에 행을 삽입하고 모든 행을 출력 할 수 있다.
지금까지 개발한 것을 테스트할 테스트 코드 작성해보자.

테스트 코드 작성을 위해 [rspec](http://rspec.info/)을 이용할 것이다. 친숙하고 읽기 쉬운 문법이기 때문이다.

짧은 helper를 정의하여 데이터베이스 프로그램에 명령 목록을 보내고 예상 출력 결과를 지정 한다.:
```ruby
describe 'database' do
  def run_script(commands)
    raw_output = nil
    IO.popen("./db", "r+") do |pipe|
      commands.each do |command|
        pipe.puts command
      end

      pipe.close_write

      # Read entire output
      raw_output = pipe.gets(nil)
    end
    raw_output.split("\n")
  end

  it 'inserts and retreives a row' do
    result = run_script([
      "insert 1 user1 person1@example.com",
      "select",
      ".exit",
    ])
    expect(result).to eq([
      "db > Executed.",
      "db > (1, user1, person1@example.com)",
      "Executed.",
      "db > ",
    ])
  end
end
```

테스트 코드 실행 후, 결과를 확인해보자.:
```command-line
bundle exec rspec
.

Finished in 0.00871 seconds (files took 0.09506 seconds to load)
1 example, 0 failures
```

이제 많은 행을 데이터베이스에 삽입하여 테스트 할 수 있다.
```ruby
it 'prints error message when table is full' do
  script = (1..1401).map do |i|
    "insert #{i} user#{i} person#{i}@example.com"
  end
  script << ".exit"
  result = run_script(script)
  expect(result[-2]).to eq('db > Error: Table full.')
end
```

다시 테스트...ㄴ
```command-line
bundle exec rspec
..

Finished in 0.01553 seconds (files took 0.08156 seconds to load)
2 examples, 0 failures
```

DB는 1400 행을 저장할 수 있다. 최대 페이지 수를 100으로 설정하고 14 행을 페이지에 넣을 수 있기 때문이다.

지금까지 작성한 코드를 읽으면 텍스트 필드를 올바르게 저장할 수 없다는 것을 알 것이다. 이 예제로 테스트하기 쉽습니다.:
```ruby
it 'allows inserting strings that are the maximum length' do
  long_username = "a"*32
  long_email = "a"*255
  script = [
    "insert 1 #{long_username} #{long_email}",
    "select",
    ".exit",
  ]
  result = run_script(script)
  expect(result).to eq([
    "db > Executed.",
    "db > (1, #{long_username}, #{long_email})",
    "Executed.",
    "db > ",
  ])
end
```

테스트 실패한다.!
```ruby
Failures:

  1) database allows inserting strings that are the maximum length
     Failure/Error: raw_output.split("\n")

     ArgumentError:
       invalid byte sequence in UTF-8
     # ./spec/main_spec.rb:14:in `split'
     # ./spec/main_spec.rb:14:in `run_script'
     # ./spec/main_spec.rb:48:in `block (2 levels) in <top (required)>'
```

직접 실행 해보면 행을 인쇄하려고 할 때 이상한 문자가 있음을 알 수 있다. ( 긴 문자열을 생략 ) :
```command-line
db > insert 1 aaaaa... aaaaa...
Executed.
db > select
(1, aaaaa...aaa\�, aaaaa...aaa\�)
Executed.
db >
```

왜 그럴까? 행의 정의한 부분을 보면 username에 32 바이트, email에는 정확히 255 바이트가 할당했다.
[C strings] (http://www.cprogramming.com/tutorial/c/lesson9.html)는 공백을 할당하지 않은 null 문자로 끝나기로 되어 있다. 해결 방법은 추가로 1 바이트를 할당하는 것이다.:
```diff
 const uint32_t COLUMN_EMAIL_SIZE = 255;
 struct Row_t {
   uint32_t id;
-  char username[COLUMN_USERNAME_SIZE];
-  char email[COLUMN_EMAIL_SIZE];
+  char username[COLUMN_USERNAME_SIZE + 1];
+  char email[COLUMN_EMAIL_SIZE + 1];
 };
 typedef struct Row_t Row;
 ```

수정 후 다시 실행 해보자.
 ```ruby
 bundle exec rspec
...

Finished in 0.0188 seconds (files took 0.08516 seconds to load)
3 examples, 0 failures
```

컬럼 크기보다 큰 username이나 email의 입력은 허용하지 않는다. 이 스펙을 적용하면 다음과 같다.:
```ruby
it 'prints error message if strings are too long' do
  long_username = "a"*33
  long_email = "a"*256
  script = [
    "insert 1 #{long_username} #{long_email}",
    "select",
    ".exit",
  ]
  result = run_script(script)
  expect(result).to eq([
    "db > String is too long.",
    "db > Executed.",
    "db > ",
  ])
end
```

이를 수행 하기 위해 파서를 업그레이드 해야 한다. 현재, [scanf()](https://linux.die.net/man/3/scanf)를 이용 중이다.:
```c
if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
  statement->type = STATEMENT_INSERT;
  int args_assigned = sscanf(
      input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
      statement->row_to_insert.username, statement->row_to_insert.email);
  if (args_assigned < 3) {
    return PREPARE_SYNTAX_ERROR;
  }
  return PREPARE_SUCCESS;
}
```

[scanf has some disadvantages](https://stackoverflow.com/questions/2430303/disadvantages-of-scanf).
읽는 문자열이 읽는 버퍼보다 ​​큰 경우 버퍼 오버플로가 발생하여 예기치 않은 위치에 쓰기 시작한다. `Row` 구조체에 복사하기 전에 각 문자열의 길이를 확인하고 싶다. 그렇게 하기 위해, 우리는 공백으로 입력을 나누어야 한다.

[strtok()](http://www.cplusplus.com/reference/cstring/strtok/)를 이용할 것이다. 다음 로직을 이해하기 쉬울 것이다.:
```diff
+PrepareResult prepare_insert(InputBuffer* input_buffer, Statement* statement) {
+  statement->type = STATEMENT_INSERT;
+
+  char* keyword = strtok(input_buffer->buffer, " ");
+  char* id_string = strtok(NULL, " ");
+  char* username = strtok(NULL, " ");
+  char* email = strtok(NULL, " ");
+
+  if (id_string == NULL || username == NULL || email == NULL) {
+    return PREPARE_SYNTAX_ERROR;
+  }
+
+  int id = atoi(id_string);
+  if (strlen(username) > COLUMN_USERNAME_SIZE) {
+    return PREPARE_STRING_TOO_LONG;
+  }
+  if (strlen(email) > COLUMN_EMAIL_SIZE) {
+    return PREPARE_STRING_TOO_LONG;
+  }
+
+  statement->row_to_insert.id = id;
+  strcpy(statement->row_to_insert.username, username);
+  strcpy(statement->row_to_insert.email, email);
+
+  return PREPARE_SUCCESS;
+}
+
 PrepareResult prepare_statement(InputBuffer* input_buffer,
                                 Statement* statement) {
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
+    return prepare_insert(input_buffer, statement);
-    statement->type = STATEMENT_INSERT;
-    int args_assigned = sscanf(
-        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
-        statement->row_to_insert.username, statement->row_to_insert.email);
-    if (args_assigned < 3) {
-      return PREPARE_SYNTAX_ERROR;
-    }
-    return PREPARE_SUCCESS;
   }
```

입력 버퍼에서 `strtok`를 연속적으로 호출하면 구분 문자 ( 여기서 공백 )에 도달 할 때마다 NULL 문자를 삽입하여 하위 문자열로 분할합니다. 부분 문자열의 시작을 가리키는 포인터를 반환한다.

각 텍스트 값에 대해 [strlen()] (http://www.cplusplus.com/reference/cstring/strlen/)을 호출하여 너무 길어질 수 있다.

다른 오류 코드처럼 오류를 처리 할 수 ​​있다.:
```diff
 enum PrepareResult_t {
   PREPARE_SUCCESS,
+  PREPARE_STRING_TOO_LONG,
   PREPARE_SYNTAX_ERROR,
   PREPARE_UNRECOGNIZED_STATEMENT
 };
```
```diff
 switch (prepare_statement(input_buffer, &statement)) {
   case (PREPARE_SUCCESS):
     break;
+  case (PREPARE_STRING_TOO_LONG):
+    printf("String is too long.\n");
+    continue;
   case (PREPARE_SYNTAX_ERROR):
     printf("Syntax error. Could not parse statement.\n");
     continue;
```

테스트 통과
```command-line
bundle exec rspec
....

Finished in 0.02284 seconds (files took 0.116 seconds to load)
4 examples, 0 failures
```

여러 오류 케이스를 다룰 수 ​​있다.:
```ruby
it 'prints an error message if id is negative' do
  script = [
    "insert -1 cstack foo@bar.com",
    "select",
    ".exit",
  ]
  result = run_script(script)
  expect(result).to eq([
    "db > ID must be positive.",
    "db > Executed.",
    "db > ",
  ])
end
```
```diff
 enum PrepareResult_t {
   PREPARE_SUCCESS,
+  PREPARE_NEGATIVE_ID,
   PREPARE_STRING_TOO_LONG,
   PREPARE_SYNTAX_ERROR,
   PREPARE_UNRECOGNIZED_STATEMENT
@@ -148,9 +147,6 @@ PrepareResult prepare_insert(InputBuffer* input_buffer, Statement* statement) {
   }

   int id = atoi(id_string);
+  if (id < 0) {
+    return PREPARE_NEGATIVE_ID;
+  }
   if (strlen(username) > COLUMN_USERNAME_SIZE) {
     return PREPARE_STRING_TOO_LONG;
   }
@@ -230,9 +226,6 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_NEGATIVE_ID):
+        printf("ID must be positive.\n");
+        continue;
       case (PREPARE_STRING_TOO_LONG):
         printf("String is too long.\n");
         continue;
```

지금은 테스트로는 충분하다. 다음 part는 매우 중요한 특징인 지속성으로 데이터베이스를 파일로 저장하고 다시 읽는다.

이번 파트에서 이전과 다른 부분이다.:
```diff
 enum PrepareResult_t {
   PREPARE_SUCCESS,
+  PREPARE_NEGATIVE_ID,
+  PREPARE_STRING_TOO_LONG,
   PREPARE_SYNTAX_ERROR,
   PREPARE_UNRECOGNIZED_STATEMENT
 };
@@ -33,8 +35,8 @@ const uint32_t COLUMN_USERNAME_SIZE = 32;
 const uint32_t COLUMN_EMAIL_SIZE = 255;
 struct Row_t {
   uint32_t id;
-  char username[COLUMN_USERNAME_SIZE];
-  char email[COLUMN_EMAIL_SIZE];
+  char username[COLUMN_USERNAME_SIZE + 1];
+  char email[COLUMN_EMAIL_SIZE + 1];
 };
 typedef struct Row_t Row;
 
@@ -133,17 +135,40 @@ MetaCommandResult do_meta_command(InputBuffer* input_buffer) {
   }
 }
 
+PrepareResult prepare_insert(InputBuffer* input_buffer, Statement* statement) {
+  statement->type = STATEMENT_INSERT;
+
+  char* keyword = strtok(input_buffer->buffer, " ");
+  char* id_string = strtok(NULL, " ");
+  char* username = strtok(NULL, " ");
+  char* email = strtok(NULL, " ");
+
+  if (id_string == NULL || username == NULL || email == NULL) {
+    return PREPARE_SYNTAX_ERROR;
+  }
+
+  int id = atoi(id_string);
+  if (id < 0) {
+    return PREPARE_NEGATIVE_ID;
+  }
+  if (strlen(username) > COLUMN_USERNAME_SIZE) {
+    return PREPARE_STRING_TOO_LONG;
+  }
+  if (strlen(email) > COLUMN_EMAIL_SIZE) {
+    return PREPARE_STRING_TOO_LONG;
+  }
+
+  statement->row_to_insert.id = id;
+  strcpy(statement->row_to_insert.username, username);
+  strcpy(statement->row_to_insert.email, email);
+
+  return PREPARE_SUCCESS;
+}
+
 PrepareResult prepare_statement(InputBuffer* input_buffer,
                                 Statement* statement) {
   if (strncmp(input_buffer->buffer, "insert", 6) == 0) {
-    statement->type = STATEMENT_INSERT;
-    int args_assigned = sscanf(
-        input_buffer->buffer, "insert %d %s %s", &(statement->row_to_insert.id),
-        statement->row_to_insert.username, statement->row_to_insert.email);
-    if (args_assigned < 3) {
-      return PREPARE_SYNTAX_ERROR;
-    }
-    return PREPARE_SUCCESS;
+    return prepare_insert(input_buffer, statement);
   }
   if (strcmp(input_buffer->buffer, "select") == 0) {
     statement->type = STATEMENT_SELECT;
@@ -205,6 +230,12 @@ int main(int argc, char* argv[]) {
     switch (prepare_statement(input_buffer, &statement)) {
       case (PREPARE_SUCCESS):
         break;
+      case (PREPARE_NEGATIVE_ID):
+        printf("ID must be positive.\n");
+        continue;
+      case (PREPARE_STRING_TOO_LONG):
+        printf("String is too long.\n");
+        continue;
       case (PREPARE_SYNTAX_ERROR):
         printf("Syntax error. Could not parse statement.\n");
         continue;
```
And we added tests:
```diff
+describe 'database' do
+  def run_script(commands)
+    raw_output = nil
+    IO.popen("./db", "r+") do |pipe|
+      commands.each do |command|
+        pipe.puts command
+      end
+
+      pipe.close_write
+
+      # Read entire output
+      raw_output = pipe.gets(nil)
+    end
+    raw_output.split("\n")
+  end
+
+  it 'inserts and retreives a row' do
+    result = run_script([
+      "insert 1 user1 person1@example.com",
+      "select",
+      ".exit",
+    ])
+    expect(result).to eq([
+      "db > Executed.",
+      "db > (1, user1, person1@example.com)",
+      "Executed.",
+      "db > ",
+    ])
+  end
+
+  it 'prints error message when table is full' do
+    script = (1..1401).map do |i|
+      "insert #{i} user#{i} person#{i}@example.com"
+    end
+    script << ".exit"
+    result = run_script(script)
+    expect(result[-2]).to eq('db > Error: Table full.')
+  end
+
+  it 'allows inserting strings that are the maximum length' do
+    long_username = "a"*32
+    long_email = "a"*255
+    script = [
+      "insert 1 #{long_username} #{long_email}",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to eq([
+      "db > Executed.",
+      "db > (1, #{long_username}, #{long_email})",
+      "Executed.",
+      "db > ",
+    ])
+  end
+
+  it 'prints error message if strings are too long' do
+    long_username = "a"*33
+    long_email = "a"*256
+    script = [
+      "insert 1 #{long_username} #{long_email}",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to eq([
+      "db > String is too long.",
+      "db > Executed.",
+      "db > ",
+    ])
+  end
+
+  it 'prints an error message if id is negative' do
+    script = [
+      "insert -1 cstack foo@bar.com",
+      "select",
+      ".exit",
+    ]
+    result = run_script(script)
+    expect(result).to eq([
+      "db > ID must be positive.",
+      "db > Executed.",
+      "db > ",
+    ])
+  end
+end
```

