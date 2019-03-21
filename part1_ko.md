# Part 1 - Introduction and Setting up the REPL

관계형 데이터베이스를 매일 이용하지만 DB는 나에게 항상 블랙박스였다.
나 스스로 질문해본다:
- 데이터 저장 포맷은 무엇인가? ( 메모리 상과 디스크 상에서 )
- 메모리에서 디스크로 언제 움직이나?
- 테이블 당 기본 키가 하나 밖에없는 이유는 무엇인가?
- 트랜젝션 롤백은 어떻게 되는가?
- 인덱스는 어떻게 포맷되는가?
- 풀스캔은 언제 어떻게 발생하는가?

다시 말해, 데이터베이스는 어떻게 _동작_ 하는가?

문제를 파악하기 위해 처음부터 데이터베이스를 개발했다.
sqlite는 MySQL 또는 PostgreSQL보다 적은 기능으로 작게 설계되었으므로 sqlite를 모델로 삼았기 때문에 이해할 수 있기 바란다. 전체 데이터베이스는 한 파일에 작성된다.

# Sqlite

 [sqlite internals on their website](https://www.sqlite.org/arch.html) 와 [SQLite Database System: Design and Implementation](https://play.google.com/store/books/details?id=9Z6IQQnX1JEC) 는 sqlite 관련 문서이다.

![sqlite arch](https://www.sqlite.org/zipvfs/doc/trunk/www/arch1.gif)

쿼리는 조회 및 데이터 수정 하기 위해 일련의 과정을 거친다. _front-end_ 의 구성 요소이다.:
- tokenizer
- parser
- code generator

front-end에 대한 입력은 SQL 쿼리이다. 출력은 sqlite 가상 머신 바이트코드이다. (기본적으로 데이터베이스에서 작동 할 수있는 컴파일 된 프로그램)

_back-end_ 의 구성 요소이다.:
- virtual machine
- B-tree
- pager
- os interface\

**virtual machine** 은 front-end에서 생성 한 바이트 코드를 지침으로 사용한다.
그런 다음 하나 이상의 테이블 또는 인덱스에서 작업을 실행할 수 있으며 각 테이블 또는 인덱스는 B 트리라는 데이터 구조에 저장된다. VM은 본질적으로 바이트 코드 명령어 유형의 큰 switch 문이다.

각각의 **B-tree**는 많은 노드들로 구성한다. 각각의 노드의 길이는 한 페이지이다.
B-tree는 pager에 명령을 발행하여 디스크에서 페이지를 검색하거나 디스크에 다시 저장할 수 있다.

**pager** 는 페이지의 데이터를 읽거나 쓰기 위해 명령어를 받는다. 데이터베이스 파일의 적절한 오프셋에서 읽기 / 쓰기를 담당한다. pager는 가장 최근에 접근한 페이지는 메모리에 캐시로 유지하고 언제 디스크에 다시 써야하는지 결정한다.

**os interface** 는 sqlite가 컴파일된 os에 따라 다른 계층이다. 이번 튜토리얼은 여러 플랫폼을 지원하지 않는다.

[A journey of a thousand miles begins with a single step](https://en.wiktionary.org/wiki/a_journey_of_a_thousand_miles_begins_with_a_single_step),
REPL을 간단하게 시작해보자.

## Making a Simple REPL

Sqlite는 명령어로 시작할 때 read-execute-print loop로 시작한다.:

```shell
~ sqlite3
SQLite version 3.16.0 2016-11-04 19:09:39
Enter ".help" for usage hints.
Connected to a transient in-memory database.
Use ".open FILENAME" to reopen on a persistent database.
sqlite> create table users (id int, username varchar(255), email varchar(255));
sqlite> .tables
users
sqlite> .exit
~
```

그렇게 하기 위해, 메인 함수는 프롬프트를 출력하고 입력 라인을 얻은 다음 그 입력 라인을 처리하는 무한 루프를 가질 것이다. :

```c
int main(int argc, char* argv[]) {
  InputBuffer* input_buffer = new_input_buffer();
  while (true) {
    print_prompt();
    read_input(input_buffer);

    if (strcmp(input_buffer->buffer, ".exit") == 0) {
      exit(EXIT_SUCCESS);
    } else {
      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
    }
  }
}
```

`InputBuffer`를 [getline()](http://man7.org/linux/man-pages/man3/getline.3.html) 과 상호 작용하기 위해 저장 해야 하는 상태를 둘러 싸는 작은 래퍼로 정의 할 것이다.
```c
struct InputBuffer_t {
  char* buffer;
  size_t buffer_length;
  ssize_t input_length;
};
typedef struct InputBuffer_t InputBuffer;

InputBuffer* new_input_buffer() {
  InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
  input_buffer->buffer = NULL;
  input_buffer->buffer_length = 0;
  input_buffer->input_length = 0;

  return input_buffer;
}
```

`print_prompt()` 함수는 유저에게 프롬프트를 출력한다. 각 입력 행을 읽기 전에이 작업을 수행한다.

```c
void print_prompt() { printf("db > "); }
```

입력 행을 읽기 위해, [getline()](http://man7.org/linux/man-pages/man3/getline.3.html)을 이용한다. :

To read a line of input, use [getline()](http://man7.org/linux/man-pages/man3/getline.3.html):
```c
ssize_t getline(char **lineptr, size_t *n, FILE *stream);
```

`linepter` : 읽은 행을 포함하는 버퍼를 가리 키기 위해 사용하는 변수에 대한 포인터

`n` : 할당된 버퍼의 크기를 저장하기 위해 사용하는 변수에 대한 포인터

`stream` : 읽는 입력 스트림 우리는 표준 입력으로부터 읽을 것입니다.

`return value` : 읽힌 바이트 수. 버퍼의 사이즈보다 작을 가능성이 있다.

`linepter` : a pointer to the variable we use to point to the buffer containing the read line.

`n` : a pointer to the variable we use to save the size of allocated buffer.

`stream` : the input stream to read from. We'll be reading from standard input.

`return value` : the number of bytes read, which may be less than the size of the buffer.

 읽은 행을 `input_buffer->buffer`와 할당된 버퍼 크기를 `input_buffer->buffer_length`에  저장 하기 위해 `getline`을 쓴다. `input_buffer->input_length` 에 반환 값을 저장한다.

`buffer` 는 null로 시작하기 때문에 `getline`은 입력 행을 저장하기 위해 충분한 메모리를 할당하고 `buffer`를 가리킨다.

```c
void read_input(InputBuffer* input_buffer) {
  ssize_t bytes_read =
      getline(&(input_buffer->buffer), &(input_buffer->buffer_length), stdin);

  if (bytes_read <= 0) {
    printf("Error reading input\n");
    exit(EXIT_FAILURE);
  }

  // Ignore trailing newline
  input_buffer->input_length = bytes_read - 1;
  input_buffer->buffer[bytes_read - 1] = 0;
}
```

마지막으로 명령어을 구문 분석하고 실행한다. 현재 인식 된 명령은 오직 하나뿐이다. : 프로그램 종료 `.exit`.
그렇지 않으면 오류 메시지를 인쇄하고 계속 반복한다.

```c
if (strcmp(input_buffer->buffer, ".exit") == 0) {
  exit(EXIT_SUCCESS);
} else {
  printf("Unrecognized command '%s'.\n", input_buffer->buffer);
}
```

실행해보자!

```shell
~ ./db
db > .tables
Unrecognized command '.tables'.
db > .exit
~
```

 우리는 작동하는 REPL을 가지고 있다. 다음 부분에서는 메모리 내에서 레코드를 만들고 검색하는 방법을 시도 할 것이다.
 한편,이 부분의 전체 프로그램은 다음과 같다.

```c
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct InputBuffer_t {
  char* buffer;
  size_t buffer_length;
  ssize_t input_length;
};
typedef struct InputBuffer_t InputBuffer;

InputBuffer* new_input_buffer() {
  InputBuffer* input_buffer = malloc(sizeof(InputBuffer));
  input_buffer->buffer = NULL;
  input_buffer->buffer_length = 0;
  input_buffer->input_length = 0;

  return input_buffer;
}

void print_prompt() { printf("db > "); }

void read_input(InputBuffer* input_buffer) {
  ssize_t bytes_read =
      getline(&(input_buffer->buffer), &(input_buffer->buffer_length), stdin);

  if (bytes_read <= 0) {
    printf("Error reading input\n");
    exit(EXIT_FAILURE);
  }

  // Ignore trailing newline
  input_buffer->input_length = bytes_read - 1;
  input_buffer->buffer[bytes_read - 1] = 0;
}

int main(int argc, char* argv[]) {
  InputBuffer* input_buffer = new_input_buffer();
  while (true) {
    print_prompt();
    read_input(input_buffer);

    if (strcmp(input_buffer->buffer, ".exit") == 0) {
      exit(EXIT_SUCCESS);
    } else {
      printf("Unrecognized command '%s'.\n", input_buffer->buffer);
    }
  }
}
```



