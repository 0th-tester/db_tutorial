CC=gcc-8
db: db.c
	$(CC) -Wall db.c -o db

run: db
	./db mydb.db

clean:
	rm -f db *.db

test: db
	rspec ./spec/main_spec.rb
	#bundle exec rspec

format: *.c
	clang-format -style=Google -i *.c