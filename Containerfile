FROM ruby:3.4-slim

WORKDIR /site

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle lock --update && bundle install

COPY . .

CMD ["bundle", "exec", "jekyll", "build"]
