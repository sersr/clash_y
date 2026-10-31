#ifndef CLASHY_CLASH_CORE_H
#define CLASHY_CLASH_CORE_H

char *startTun(char *configDir, int fd);
char *stop(void);
void freeString(char *message);

#endif
